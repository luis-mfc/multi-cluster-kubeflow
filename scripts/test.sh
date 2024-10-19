#!/bin/bash
#
# Basic testing:
#  - check that the istio mesh works: ensure a service in cluster A can accessed from a pods on cluster B
#  - check that admiralty scheduling works: create one to run in each cluster (but submitted in a single one)
#  - check that kubeflow notebooks work: creating 1 in each cluster (but submitted in a single one)
#

set -eu -o pipefail

source ".env"

istio() {
  local -r namespace=istio-test

  kubectl --context "$DC_CLUSTER_CONTEXT" create ns "$namespace" || true
  kubectl --context "$CLOUD_CLUSTER_CONTEXT" create ns "$namespace" || true

  kubectl --context "$DC_CLUSTER_CONTEXT" label ns "$namespace" istio-injection=enabled --overwrite
  kubectl --context "$CLOUD_CLUSTER_CONTEXT" label ns "$namespace" istio-injection=enabled --overwrite

  kubectl --context "$DC_CLUSTER_CONTEXT" apply -n "$namespace" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox
spec:
  replicas: 1
  selector:
    matchLabels:
      app: busybox
  template:
    metadata:
      labels:
        app: busybox
    spec:
      containers:
      - name: busybox
        image: busybox
        command:
          - sleep
          - inf
        ports:
        - containerPort: 80
EOF

  kubectl --context "$CLOUD_CLUSTER_CONTEXT" apply -n "$namespace" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
EOF

  kubectl wait pod -l app=busybox \
    --context "$DC_CLUSTER_CONTEXT" \
    -n "$namespace" \
    --for=condition=ready \
    --timeout=60s
  kubectl wait pod -l app=nginx \
    --context "$CLOUD_CLUSTER_CONTEXT" \
    -n "$namespace" \
    --for=condition=ready \
    --timeout=60s

  # shellcheck disable=SC2028
  while timeout -k 60 60 -- wget -O- "http://nginx:80"; [ $? = 124 ] ; do sleep 2  ; done
  kubectl --context "$DC_CLUSTER_CONTEXT" exec -n "$namespace" deploy/busybox -- \
    timeout 60 sh -c 'until wget -O- "http://nginx:80"; do echo Request failed ; sleep 5; done'
}

admiralty() {
  local -r namespace=admiralty-test

  kubectl --context "$DC_CLUSTER_CONTEXT" create ns "$namespace" || true
  kubectl --context "$CLOUD_CLUSTER_CONTEXT" create ns "$namespace" || true

  kubectl \
    --context "$DC_CLUSTER_CONTEXT" \
    label ns $namespace "multicluster-scheduler=enabled"

  for cluster in "${CLUSTERS[@]}"; do
    kubectl --context "$DC_CLUSTER_CONTEXT" apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: test-job-$cluster
  namespace: $namespace
spec:
  ttlSecondsAfterFinished: 10
  template:
    metadata:
      annotations:
        multicluster.admiralty.io/elect: ""
        # https://github.com/admiraltyio/admiralty/issues/201#issuecomment-1861798315
        multicluster.admiralty.io/no-reservation: ""
        multicluster.admiralty.io/use-constraints-from-spec-for-proxy-pod-scheduling: ""
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                - key: multicluster.admiralty.io/cluster-target-name
                  operator: In
                  values:
                    - $cluster
      containers:
      - name: c
        image: busybox
        command: ["sh", "-exc", "echo test job on cluster $cluster && sleep 5"]
      restartPolicy: Never
EOF
    kubectl wait "job/test-job-$cluster" \
      --context "$DC_CLUSTER_CONTEXT" \
      --namespace "$namespace" \
      --for=condition=complete \
      --timeout=60s
  done
}

kubeflow_notebook() {
  local -r namespace=kubeflow-user-example-com

  echo "Waiting for namespace $namespace to be created in context $DC_CLUSTER_NAME..."
  while ! kubectl --context "$DC_CLUSTER_CONTEXT" get namespace "$namespace" >/dev/null 2>&1; do
    sleep 1
  done

  kubectl \
    --context "$DC_CLUSTER_CONTEXT" \
    label ns $namespace "multicluster-scheduler=enabled"

  # add admiralty annotations to the notebook pods
  kubectl apply --context "$DC_CLUSTER_CONTEXT" -f - <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-annotation-to-pods
  annotations:
    policies.kyverno.io/title: Add Annotation to Pods
    policies.kyverno.io/category: Pod Management
    policies.kyverno.io/severity: low
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Adds a custom annotation to all pods in the specified namespace.
spec:
  rules:
  - name: add-annotation
    match:
      any:
      - resources:
          kinds:
            - Pod
          namespaces:
            - $namespace
    mutate:
      patchStrategicMerge:
        metadata:
          annotations:
            multicluster.admiralty.io/elect: ""
            multicluster.admiralty.io/no-reservation: ""
            multicluster.admiralty.io/use-constraints-from-spec-for-proxy-pod-scheduling: ""
EOF

  for cluster in "${CLUSTERS[@]}"; do
    kubectl --context "$DC_CLUSTER_CONTEXT" apply -f - <<EOF
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  annotations:
    notebooks.kubeflow.org/creator: user@example.com
    notebooks.kubeflow.org/http-rewrite-uri: /
    notebooks.kubeflow.org/server-type: group-one
  labels:
    app: test-notebook-on-$cluster
    admiralty: 'true'
  name: test-notebook-on-$cluster
  namespace: $namespace
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                - key: multicluster.admiralty.io/cluster-target-name
                  operator: In
                  values:
                    - $cluster
      containers:
        - name: test-notebook-on-$cluster
          image: kubeflownotebookswg/codeserver-python:v1.8.0
          resources:
            limits:
              memory: 1Gi
            requests:
              cpu: '0.5'
              memory: 1Gi
          volumeMounts:
            - mountPath: /dev/shm
              name: dshm
      serviceAccountName: default-editor
      tolerations: []
      volumes:
        - emptyDir:
            medium: Memory
          name: dshm
EOF
    echo "Waiting for notebook to start on cluster '$cluster' ..."
    sleep 5 # pod may take a bit to get created
    kubectl wait pod -l "statefulset=test-notebook-on-$cluster" \
      --context "$DC_CLUSTER_CONTEXT" \
      -n "$namespace" \
      --for=condition=ready \
      --timeout=60s
  done
}

echo -e "\033[34mTesting the istio mesh ...\033[0m"
istio

echo
echo -e "\033[34mTesting multi cluster scheduling via admiralty ...\033[0m"
admiralty
echo

echo
echo -e "\033[34mTesting multi cluster Kubeflow notebooks ...\033[0m"
kubeflow_notebook
