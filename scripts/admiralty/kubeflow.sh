#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../../.env"

label_cluster_nodes() {
  cluster=$1

  kubectl label nodes \
    --all "topology.kubernetes.io/region=$cluster" \
    --context "kind-$cluster" \
    --overwrite
}

cross_cluster_authentication() {
  dc_cluster=$1
  target_cluster=$2
  namespace=$3

  kubectl \
    --context "kind-$target_cluster" \
    create serviceaccount "$dc_cluster" \
    -n "$namespace" || true

  TOKEN=$(kubectl --context "kind-$target_cluster" create token "$dc_cluster" -n "$namespace")
  IP=$(kubectl --context "kind-$target_cluster" get nodes -o wide | tail -n 1 | awk '{print $6}')
  CONFIG="$(kubectl --context "kind-$target_cluster" config view --minify=true --raw --output json |
    jq '.users[0].user={token:"'$TOKEN'"} | .clusters[0].cluster.server="https://'$IP':6443"')"

  echo "TOKEN=$TOKEN"
  echo "IP=$IP"
  echo "CONFIG=$CONFIG"

  kubectl \
    --context "kind-$dc_cluster" \
    create secret generic "$target_cluster" \
    --from-literal=config="$CONFIG" \
    -n "$namespace" || true
}

multi_cluster_scheduling() {
  dc_cluster=$1
  target_cluster=$2
  namespace=$3

  # Create a Target for each workload cluster:
  cat <<EOF | kubectl --context "kind-$dc_cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: Target
metadata:
  name: $target_cluster
  namespace: $namespace
spec:
  kubeconfigSecret:
    name: $target_cluster
EOF

  # In the workload cluster, create a Source for the management cluster:
  cat <<EOF | kubectl --context "kind-$target_cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: Source
metadata:
  name: $dc_cluster
  namespace: $namespace
spec:
  serviceAccountName: $dc_cluster
EOF
}

self_cluster_scheduling() {
  cluster=$1
  namespace=$2

  # Create a Target for the self cluster:
  cat <<EOF | kubectl --context "kind-$cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: Target
metadata:
  name: $1
  namespace: $namespace
spec:
  self: true
EOF
}

for cluster in "${CLUSTERS[@]}"; do
  label_cluster_nodes "$cluster"
done

DC_CLUSTER_NAME="${CLUSTERS[0]}"
CLOUD_CLUSTER_NAME="${CLUSTERS[1]}"

kubectl --context "kind-$DC_CLUSTER_NAME" label ns default multicluster-scheduler=enabled
cross_cluster_authentication "$DC_CLUSTER_NAME" "$CLOUD_CLUSTER_NAME" default
multi_cluster_scheduling "$DC_CLUSTER_NAME" "$CLOUD_CLUSTER_NAME" default
self_cluster_scheduling "$DC_CLUSTER_NAME" default

# echo "Kubeflow setup..."

# wait_for_namespace() {
#   cluster=$1
#   namespace=$2

#   echo "Waiting for namespace $namespace to be created in context $cluster..."
#   while ! kubectl --context "kind-$cluster" get namespace "$namespace" >/dev/null 2>&1; do
#     sleep 1
#   done
# }

# for cluster in "${CLUSTERS[@]}"; do
#   wait_for_namespace "$cluster" kubeflow-user-example-com # created my kubeflow
# done

# kubectl --context "kind-$DC_CLUSTER_NAME" label ns kubeflow-user-example-com multicluster-scheduler=enabled
# cross_cluster_authentication "$DC_CLUSTER_NAME" "$CLOUD_CLUSTER_NAME" kubeflow-user-example-com
# multi_cluster_scheduling "$DC_CLUSTER_NAME" "$CLOUD_CLUSTER_NAME" kubeflow-user-example-com
# kubectl --context "kind-$DC_CLUSTER_NAME" label ns default multicluster-scheduler=enabled
# cross_cluster_authentication "$DC_CLUSTER_NAME" "$DC_CLUSTER_NAME" default
# multi_cluster_scheduling "$DC_CLUSTER_NAME" "$DC_CLUSTER_NAME" default
