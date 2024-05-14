#!/bin/bash

# Exit on error
set -eux -o pipefail

source "$(dirname $0)/../../.env"

install_dependencies() {
  local $cluster=$1

  helm repo add jetstack https://charts.jetstack.io
  helm repo update >/dev/null

  helm upgrade --install cert-manager jetstack/cert-manager \
    --kube-context "kind-$cluster" \
    --namespace cert-manager \
    --create-namespace \
    --version v1.13.1 \
    --set installCRDs=true \
    --atomic \
    --wait

  helm upgrade --install admiralty oci://public.ecr.aws/admiralty/admiralty \
    --kube-context "kind-$cluster" \
    --namespace admiralty \
    --create-namespace \
    --version 0.16.0 \
    --atomic \
    --wait
}

create_cluster() {
  local cluster=$1
  local kubernetes_version=$2

  kind create cluster \
    --name "$cluster" \
    --image "kindest/node:$kubernetes_version"
  install_dependencies "$cluster"
}

cross_cluster_authentication() {
  management_cluster=$1
  workload_cluster=$2

  kubectl label nodes \
    --all "topology.kubernetes.io/region=$workload_cluster" \
    --context "kind-$workload_cluster"

  kubectl \
    --context "kind-$workload_cluster" \
    create serviceaccount "$management_cluster" || true

  TOKEN=$(kubectl --context "kind-$workload_cluster" create token "$management_cluster")
  IP=$(kubectl --context "kind-$workload_cluster" get nodes -o wide | tail -n 1 | awk '{print $6}')
  CONFIG="$(kubectl --context "kind-$workload_cluster" config view --minify=true --raw --output json |
    jq '.users[0].user={token:"'$TOKEN'"} | .clusters[0].cluster.server="https://'$IP':6443"')"

  echo "TOKEN=$TOKEN"
  echo "IP=$IP"
  echo "CONFIG=$CONFIG"

  kubectl \
    --context "kind-$management_cluster" \
    create secret generic "$workload_cluster" \
    --from-literal=config="$CONFIG"
}

multi_cluster_scheduling() {
  management_cluster=$1
  workload_cluster=$2

  # Create a Target for each workload cluster:
  cat <<EOF | kubectl --context "kind-$management_cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: Target
metadata:
  name: $workload_cluster
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
spec:
  serviceAccountName: $management_cluster
EOF
}

echo "Creating clusters..."
create_cluster "${CLUSTERS[0]}" "$KUBERNETES_VERSION"
create_cluster "${CLUSTERS[1]}" "$KUBERNETES_VERSION"

echo "Cross cluster auth setup..."
cross_cluster_authentication "${CLUSTERS[0]}" "${CLUSTERS[1]}"

echo "Multi cluster scheduling..."
multi_cluster_scheduling "${CLUSTERS[0]}" "${CLUSTERS[1]}"
