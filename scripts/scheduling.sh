#!/bin/bash
#
# Cloud bursting admiralty setup:
#   - https://admiralty.io/docs/concepts/topologies/#cloud-bursting
#   - https://admiralty.io/docs/operator_guide/scheduling
#

set -eu -o pipefail

source "$(dirname "$0")/../.env"

cross_cluster_authentication() {
  cluster=$1
  target_cluster=$2
  target_cluster_name="$(kubectl --context "$target_cluster" config view --minify -o jsonpath='{.clusters[].name}')"
  namespace=$3

  kubectl \
    --context "$target_cluster" \
    create serviceaccount "$cluster" \
    -n "$namespace" || true

  TOKEN=$(kubectl --context "$target_cluster" create token "$cluster" -n "$namespace")
  IP=$(kubectl --context "$target_cluster" get nodes -o wide | tail -n 1 | awk '{print $6}')
  CONFIG="$(kubectl --context "$target_cluster" config view --minify=true --raw --output json |
    jq '.users[0].user={token:"'"$TOKEN"'"} | .clusters[0].cluster.server="https://'"$IP"':6443"')"

  kubectl \
    --context "$target_cluster" \
    create secret generic "$target_cluster" \
    --from-literal=config="$CONFIG" \
    -n "$namespace" || true
}

multi_cluster_scheduling() {
  cluster=$1
  cluster_name="$(kubectl --context "$cluster" config view --minify -o jsonpath='{.clusters[].name}')"
  target_cluster=$2
  target_cluster_name="$(kubectl --context "$target_cluster" config view --minify -o jsonpath='{.clusters[].name}')"
  namespace=$3

  cat <<EOF | kubectl --context "$cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: ClusterTarget
metadata:
  name: $target_cluster_name
spec:
  kubeconfigSecret:
    name: $target_cluster_name
    namespace: $namespace
EOF

  cat <<EOF | kubectl --context "$target_cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: ClusterSource
metadata:
  name: $cluster_name
spec:
  serviceAccount:
    name: $cluster
    namespace: $namespace
EOF
}

self_cluster_scheduling() {
  cluster=$1
  cluster_name="$(kubectl --context "$cluster" config view --minify -o jsonpath='{.clusters[].name}')"

  # Create a Target for the self cluster:
  cat <<EOF | kubectl --context "$cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: ClusterTarget
metadata:
  name: $cluster_name
spec:
  self: true
EOF
}

cross_cluster_authentication "$DC_CLUSTER_CONTEXT" "$CLOUD_CLUSTER_CONTEXT" default
multi_cluster_scheduling "$DC_CLUSTER_CONTEXT" "$CLOUD_CLUSTER_CONTEXT" default
self_cluster_scheduling "$DC_CLUSTER_CONTEXT"
