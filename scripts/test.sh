#!/bin/bash

set -eu -o pipefail

source "$(dirname "$0")/../.env"

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

  kubectl --context "$CLOUD_CLUSTER_CONTEXT" apply -n test -f - <<EOF
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
  kubectl --context "$DC_CLUSTER_CONTEXT" wait -n test --for=condition=ready pod -l app=busybox
  kubectl --context "$CLOUD_CLUSTER_CONTEXT" wait -n test --for=condition=ready pod -l app=nginx
  # shellcheck disable=SC2028
  kubectl --context "$DC_CLUSTER_CONTEXT" exec -n test deploy/busybox -- wget -O- "http://nginx:80"
}

basic_scheduling() {
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
    kubectl wait --context "$DC_CLUSTER_CONTEXT" "job/test-job-$cluster" \
      --namespace "$namespace" \
      --for=condition=complete \
      --timeout=60s
  done
}

kubeflow_notebook() {
  local -r namespace=kubeflow-user-example-com

  echo "Waiting for namespace $namespace to be created in context $cluster..."
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
  done
}

istio
echo "Basic istio mesh setup working between clusters"

basic_scheduling
echo "Basic scheduling working via admiralty"

kubeflow_notebook
echo "Kubeflow notebook created, port-forward to test it"
