#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../../.env"

# install_dependencies() {
#   local cluster=$1
#   local values=$2

#   helm repo add karmada-charts https://raw.githubusercontent.com/karmada-io/karmada/master/charts
#   helm repo update >/dev/null

#   echo "Installing dependencies on cluster $cluster..."
#   set -x
#   helm upgrade --install karmada karmada-charts/karmada \
#     --kube-context "kind-$cluster" \
#     --namespace karmada-system \
#     --create-namespace \
#     --version v1.9.0 \
#     --set karmadaImageVersion=v1.9.1 \
#     --atomic \
#     --wait \
#     -f - <<EOF
# $values
# EOF
#   set +x
# }

# install_dependencies "aws" "host"
# install_dependencies "dc" "agent" <<EOF
# installMode: "agent"
# agent:
#   clusterName: "dc"
#   clusterEndpoint: "https://172.18.0.2:6443"
#   ## kubeconfig of the karmada
#   kubeconfig:
#     caCrt: |
#       -----BEGIN CERTIFICATE-----
#       XXXXXXXXXXXXXXXXXXXXXXXXXXX
#       -----END CERTIFICATE-----
#     crt: |
#       -----BEGIN CERTIFICATE-----
#       XXXXXXXXXXXXXXXXXXXXXXXXXXX
#       -----END CERTIFICATE-----
#     key: |
#       -----BEGIN RSA PRIVATE KEY-----
#       XXXXXXXXXXXXXXXXXXXXXXXXXXX
#       -----END RSA PRIVATE KEY-----
#     server: "https://apiserver.karmada"
# EOF
