#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../.env"

install_dependencies() {
  local profile=$1

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
  local network=$3
  local static_ip=$4

  set -x
  minikube status -p "$profile" >/dev/null 2>&1 || minikube start \
    -p "$profile" \
    --kubernetes-version "$kubernetes_version" \
    --network "$network" \
    --static-ip "$static_ip"
  set +x
  install_dependencies "$profile"
}

cross_cluster_authentication() {
  management_cluster=$1
  workload_cluster=$2

  kubectl label nodes \
    --all "topology.kubernetes.io/region=$workload_cluster" \
    --context "$workload_cluster"

  kubectl \
    --context "$workload_cluster" \
    create serviceaccount "$management_cluster" || true

  TOKEN=$(kubectl --context "$workload_cluster" create token "$management_cluster")
  IP=$(kubectl config view | yq ".clusters[] | select(.name == \"$workload_cluster\") | .cluster.server" |
    awk -F/ '{print $3}' | awk -F: '{print $1}')
  CONFIG=$(kubectl --context "$workload_cluster" config view --minify=true --raw --output json |
    jq '.users[0].user={token:"'$TOKEN'"} | .clusters[0].cluster.server="https://'$IP':6443"')

  echo "TOKEN=$TOKEN"
  echo "IP=$IP"
  echo "CONFIG=$CONFIG"

  kubectl \
    --context "$management_cluster" \
    create secret generic "$workload_cluster" \
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
  name: $management_cluster
spec:
  serviceAccountName: $management_cluster
EOF
}

docker network create \
  --driver=bridge \
  --subnet=192.168.49.0/24 \
  --gateway=192.168.49.1 -o \
  --ip-masq -o \
  --icc -o com.docker.network.driver.mtu=65535 \
  --label=created_by.minikube.sigs.k8s.io=true \
  --label=name.minikube.sigs.k8s.io=minikube "$NETWORK_NAME"

echo "Creating clusters..."
create_cluster "${CLUSTERS[0]}" "$KUBERNETES_VERSION" "$NETWORK_NAME" "192.168.49.2"
create_cluster "${CLUSTERS[1]}" "$KUBERNETES_VERSION" "$NETWORK_NAME" "192.168.49.3"

echo "Cross cluster auth setup..."
cross_cluster_authentication "${CLUSTERS[0]}" "${CLUSTERS[1]}"

echo "Multi cluster scheduling..."
multi_cluster_scheduling "${CLUSTERS[0]}" "${CLUSTERS[1]}"
