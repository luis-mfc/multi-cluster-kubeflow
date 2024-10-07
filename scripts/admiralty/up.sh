#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../../.env"

install_dependencies() {
  local cluster=$1

  helm repo add jetstack https://charts.jetstack.io >/dev/null
  helm repo update >/dev/null

  echo "Installing dependencies on cluster $cluster..."

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

for cluster in "${CLUSTERS[@]}"; do
  install_dependencies "$cluster"
done

kubectl config use-context kind-dc
