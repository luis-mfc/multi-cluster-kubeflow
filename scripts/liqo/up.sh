#!/bin/bash

# Exit on error
set -eux

source "$(dirname "$0")/../../.env"

install_dependencies() {
  local cluster=$1

  helm repo add liqo https://helm.liqo.io/ >/dev/null
  helm repo update >/dev/null

  local serviceCIDR
  local podCIDR
  serviceCIDR="$(kubectl --context "kind-$cluster" cluster-info dump | grep -m 1 service-cluster-ip-range | cut -d "=" -f2 | tr -d , | tr -d "\"")"
  podCIDR="$(kubectl --context "kind-$cluster" cluster-info dump | grep -m 1 podCIDR | tr -d , | cut -d ":" -f2 | tr -d "\"" | xargs)"

  helm upgrade --install liqo liqo/liqo \
    --kube-context "kind-$cluster" \
    --namespace liqo \
    --create-namespace \
    --set "tag=v0.10.3" \
    --set "discovery.config.clusterName=kind-$cluster" \
    --set "networkManager.config.serviceCIDR=$serviceCIDR" \
    --set "networkManager.config.podCIDR=$podCIDR" \
    --atomic \
    --wait
}

create_cluster() {
  local cluster=$1
  local kubernetes_version=$2

  kind get clusters | grep "$cluster" > /dev/null || kind create cluster \
    --name "$cluster" \
    --image "kindest/node:$kubernetes_version"
  install_dependencies "$cluster"
}

echo "Creating clusters..."
create_cluster "${CLUSTERS[0]}" "$KUBERNETES_VERSION"
create_cluster "${CLUSTERS[1]}" "$KUBERNETES_VERSION"
