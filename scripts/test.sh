#!/bin/bash

set -eu -o pipefail

source "$(dirname "$0")/../.env"

istio() {
  kubectl --context=dc create ns test || true
  kubectl --context=aws create ns test || true

  kubectl --context=dc label namespace test istio-injection=enabled --overwrite
  kubectl --context=aws label namespace test istio-injection=enabled --overwrite

  kubectl --context=dc apply -n test -f - <<EOF
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

  kubectl --context=aws apply -n test -f - <<EOF
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
  kubectl --context dc wait -n test --for=condition=ready pod -l app=busybox
  kubectl --context aws wait -n test --for=condition=ready pod -l app=nginx
  # shellcheck disable=SC2028
  kubectl --context dc exec -n test deploy/busybox -- wget -O- "http://nginx:80" ||
    (echo "\033[0;31m basic istio testing failed" && exit 1)
}

basic_scheduling() {
  management_cluster="${CLUSTERS[0]}"

  kubectl \
    --context "$management_cluster" \
    label ns default "multicluster-scheduler=enabled"

  for i in $(seq 1 0); do
    cat <<EOF | kubectl --context "$management_cluster" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: global-$i
  namespace: default
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
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 1
              preference:
                matchExpressions:
                - key: multicluster.admiralty.io/cluster-target-name
                  operator: In
                  values:
                  - dc
      containers:
      - name: c
        image: busybox
        command: ["sh", "-exc", "echo Processing item $i && sleep 5"]
      restartPolicy: Never
EOF
  done
}

kubeflow_notebook() {
  kubectl create \
    --context "$management_cluster" \
    -f https://github.com/kyverno/kyverno/releases/download/v1.11.1/install.yaml 2>/dev/null || true

  wait_for_namespace() {
    cluster=$1
    namespace=$2

    echo "Waiting for namespace $namespace to be created in context $cluster..."
    while ! kubectl --context "$cluster" get namespace "$namespace" >/dev/null 2>&1; do
      sleep 1
    done
  }

  wait_for_namespace "$management_cluster" "kubeflow-user-example-com"
  kubectl \
    --context "$management_cluster" \
    label ns kubeflow-user-example-com "multicluster-scheduler=enabled"

  kubectl apply --context "$management_cluster" -f - <<EOF
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
            - kubeflow-user-example-com
    mutate:
      patchStrategicMerge:
        metadata:
          annotations:
            multicluster.admiralty.io/elect: ""
            multicluster.admiralty.io/no-reservation: ""
            multicluster.admiralty.io/use-constraints-from-spec-for-proxy-pod-scheduling: ""
            # sidecar.istio.io/inject: "false"
EOF

  kubectl replace --force --context "$management_cluster" -f - <<EOF
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  annotations:
    notebooks.kubeflow.org/creator: user@example.com
    notebooks.kubeflow.org/http-rewrite-uri: /
    notebooks.kubeflow.org/server-type: group-one
  labels:
    app: test-notebook
    admiralty: 'true'
  name: test-notebook
  namespace: kubeflow-user-example-com
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
                    - aws
          # preferredDuringSchedulingIgnoredDuringExecution:
          #   - weight: 1
          #     preference:
          #       matchExpressions:
          #       - key: multicluster.admiralty.io/cluster-target-name
          #         operator: In
          #         values:
          #           - dc
      containers:
        - name: test-notebook
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
}

istio
echo "Basic istio mesh setup working between clusters"

basic_scheduling
echo "Basic scheduling working via admiralty"

kubeflow_notebook
echo "Kubeflow notebook created, port-forward to test it"
