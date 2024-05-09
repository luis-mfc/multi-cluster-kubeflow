#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../.env"

install_dependencies() {
  local profile=$1

  kubectl label nodes \
    --all "topology.kubernetes.io/region=$profile" \
    --context "$profile"

  helm repo add jetstack https://charts.jetstack.io
  helm repo update >/dev/null

  helm upgrade --install cert-manager jetstack/cert-manager \
    --kube-context "$profile" \
    --namespace cert-manager \
    --create-namespace \
    --version v1.13.1 \
    --set installCRDs=true \
    --atomic \
    --wait

  helm upgrade --install admiralty oci://public.ecr.aws/admiralty/admiralty \
    --kube-context "$profile" \
    --namespace admiralty \
    --create-namespace \
    --version 0.16.0 \
    --atomic \
    --wait
}

create_cluster() {
  local profile=$1
  local kubernetes_version=$2

  set -x
  minikube status -p "$profile" >/dev/null 2>&1 || minikube start \
    -p "$profile" \
    --kubernetes-version "$kubernetes_version"
  set +x
  install_dependencies "$profile"
}

cross_cluster_authentication() {
  management_cluster=$1
  workload_cluster=$2

  kubectl \
    --context "$workload_cluster" \
    create serviceaccount cd || true

  TOKEN=$(kubectl --context "$workload_cluster" create token cd)
  IP=$(kubectl config view | yq ".clusters[] | select(.name == \"$workload_cluster\") | .cluster.server" |
    awk -F/ '{print $3}' | awk -F: '{print $1}')
  CONFIG=$(kubectl --context "$workload_cluster" config view --minify=true --raw --output json |
    jq '.users[0].user={token:"'$TOKEN'"} | .clusters[0].cluster.server="https://'$IP':6443"')

  echo "TOKEN=$TOKEN"
  echo "IP=$IP"
  echo "CONFIG=$CONFIG"

  kubectl \
    --context "$workload_cluster" \
    create secret generic "$management_cluster" \
    --from-literal=config="$CONFIG"
}

multi_cluster_scheduling() {
  management_cluster=$1
  workload_cluster=$2

  # Create a Target for each workload cluster:
  cat <<EOF | kubectl --context "$management_cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: Target
metadata:
  name: $workload_cluster
spec:
  kubeconfigSecret:
    name: $workload_cluster
EOF

  # In the workload cluster, create a Source for the management cluster:
  cat <<EOF | kubectl --context "$workload_cluster" apply -f -
apiVersion: multicluster.admiralty.io/v1alpha1
kind: Source
metadata:
  name: aws
spec:
  serviceAccountName: aws
EOF
}

echo "Creating clusters..."
for cluster in "${CLUSTERS[@]}"; do
  create_cluster "$cluster" "$KUBERNETES_VERSION"
done

echo "Cross cluster auth setup..."
cross_cluster_authentication "${CLUSTERS[0]}" "${CLUSTERS[1]}"

echo "Multi cluster scheduling..."
multi_cluster_scheduling "${CLUSTERS[0]}" "${CLUSTERS[1]}"
