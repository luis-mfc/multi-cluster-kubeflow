#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../../.env"

cross_cluster_authentication() {
  management_cluster=$1
  workload_cluster=$2
  namespace=$3

  kubectl label nodes \
    --all "topology.kubernetes.io/region=$workload_cluster" \
    --context "kind-$workload_cluster"

  kubectl \
    --context "kind-$workload_cluster" \
    create serviceaccount "$management_cluster" \
    -n "$namespace" || true

  TOKEN=$(kubectl --context "kind-$workload_cluster" create token "$management_cluster" -n "$namespace")
  IP=$(kubectl --context "kind-$workload_cluster" get nodes -o wide | tail -n 1 | awk '{print $6}')
  CONFIG="$(kubectl --context "kind-$workload_cluster" config view --minify=true --raw --output json |
    jq '.users[0].user={token:"'$TOKEN'"} | .clusters[0].cluster.server="https://'$IP':6443"')"

  echo "TOKEN=$TOKEN"
  echo "IP=$IP"
  echo "CONFIG=$CONFIG"

  kubectl \
    --context "kind-$management_cluster" \
    create secret generic "$workload_cluster" \
    --from-literal=config="$CONFIG" \
    -n "$namespace" || true
}

multi_cluster_scheduling() {
  management_cluster=$1
  workload_cluster=$2
  namespace=$3

  # Create a Target for each workload cluster:
  cat <<EOF | kubectl --context "kind-$management_cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: Target
metadata:
  name: $workload_cluster
  namespace: $namespace
spec:
  kubeconfigSecret:
    name: $workload_cluster
EOF

  # In the workload cluster, create a Source for the management cluster:
  cat <<EOF | kubectl --context "kind-$workload_cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: Source
metadata:
  name: $management_cluster
  namespace: $namespace
spec:
  serviceAccountName: $management_cluster
EOF
}

echo "Kubeflow setup..."

wait_for_namespace() {
  cluster=$1
  namespace=$2

  echo "Waiting for namespace $namespace to be created in context $cluster..."
  while ! kubectl --context "kind-$cluster" get namespace "$namespace" >/dev/null 2>&1; do
    sleep 1
  done
}

# Create user namespace
wait_for_namespace "${CLUSTERS[0]}" kubeflow-user-example-com # created my kubeflow
# TODO: potentially install via kubeflow
kubectl create namespace \
  --context "kind-${CLUSTERS[1]}" \
  "kubeflow-user-example-com" || true

kubectl --context "kind-${CLUSTERS[0]}" label ns kubeflow-user-example-com multicluster-scheduler=enabled
cross_cluster_authentication "${CLUSTERS[0]}" "${CLUSTERS[1]}" kubeflow-user-example-com
multi_cluster_scheduling "${CLUSTERS[0]}" "${CLUSTERS[1]}" kubeflow-user-example-com

kubectl --context "kind-${CLUSTERS[0]}" label ns default multicluster-scheduler=enabled
cross_cluster_authentication "${CLUSTERS[0]}" "${CLUSTERS[1]}" default
multi_cluster_scheduling "${CLUSTERS[0]}" "${CLUSTERS[1]}" default
