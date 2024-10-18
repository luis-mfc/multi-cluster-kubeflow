#!/bin/bash
#
# Cloud bursting admiralty setup:
#   - https://admiralty.io/docs/concepts/topologies/#cloud-bursting
#   - https://admiralty.io/docs/operator_guide/scheduling
#

set -eu -o pipefail

source "$(dirname "$0")/../.env"

cross_cluster_authentication() {
  kubectl \
    --context "$CLOUD_CLUSTER_CONTEXT" \
    create serviceaccount "$DC_CLUSTER_NAME" \
    -n "admiralty" || true

  TOKEN=$(kubectl --context "$CLOUD_CLUSTER_CONTEXT" create token "$DC_CLUSTER_NAME" -n "admiralty")
  CONFIG="$(kubectl --context "$CLOUD_CLUSTER_CONTEXT" config view --minify=true --raw --output json |
    jq '.users[0].user={token:"'"$TOKEN"'"}')"

  kubectl \
    --context "$DC_CLUSTER_CONTEXT" \
    create secret generic "$CLOUD_CLUSTER_NAME" \
    --from-literal=config="$CONFIG" \
    -n "admiralty" || true
}

multi_cluster_scheduling() {
  kubectl --context "$DC_CLUSTER_CONTEXT" apply -f - <<EOF
apiVersion: multicluster.admiralty.io/v1alpha1
kind: ClusterTarget
metadata:
  name: $CLOUD_CLUSTER_NAME
spec:
  kubeconfigSecret:
    name: $CLOUD_CLUSTER_NAME
    namespace: admiralty
EOF

  kubectl --context "$CLOUD_CLUSTER_CONTEXT" apply -f - <<EOF
apiVersion: multicluster.admiralty.io/v1alpha1
kind: ClusterSource
metadata:
  name: $DC_CLUSTER_NAME
spec:
  serviceAccount:
    name: $DC_CLUSTER_NAME
    namespace: admiralty
EOF
}

self_cluster_scheduling() {
  kubectl --context "$DC_CLUSTER_CONTEXT" apply -f - <<EOF
apiVersion: multicluster.admiralty.io/v1alpha1
kind: ClusterTarget
metadata:
  name: $DC_CLUSTER_NAME
spec:
  self: true
EOF
}

cross_cluster_authentication
multi_cluster_scheduling
self_cluster_scheduling
