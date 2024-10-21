#!/bin/bash
#
# Istio multi-cluster setup based on:
#   - https://github.com/mlkmhd/istio-multi-cluster-initializer
#   - https://istio.io/latest/docs/setup/install/multicluster/
#

set -eu -o pipefail

source ".env"

CERT_DIR=".certs"
MANIFESTS_DIR="$(dirname "$0")/../manifests/istio"

prepare_certs() {
  echo "Clean up contents of dir '$CERT_DIR'"
  rm -rf "${CERT_DIR}"

  echo "Generating new certificates"

  mkdir -p "${CERT_DIR}"

  step certificate create root.istio.io "${CERT_DIR}/root-cert.pem" "${CERT_DIR}/root-ca.key" \
    --profile root-ca --no-password --insecure --san root.istio.io \
    --not-after 87600h --kty RSA

  for cluster in "${CLUSTERS[@]}"; do
    mkdir -p "${CERT_DIR}/$cluster"

    step certificate create "$cluster.intermediate.istio.io" "${CERT_DIR}/$cluster/ca-cert.pem" "${CERT_DIR}/$cluster/ca-key.pem" \
      --ca "${CERT_DIR}/root-cert.pem" \
      --ca-key "${CERT_DIR}/root-ca.key" \
      --profile intermediate-ca \
      --not-after 87600h \
      --no-password \
      --insecure \
      --san "$cluster.intermediate.istio.io" \
      --kty RSA

    cat "${CERT_DIR}/$cluster/ca-cert.pem" "${CERT_DIR}/root-cert.pem" >"${CERT_DIR}/$cluster/cert-chain.pem"
  done
}

install() {
  for cluster_index in "${!CONTEXTS[@]}"; do
    local cluster="${CLUSTERS[$cluster_index]}"
    local context="${CONTEXTS[$cluster_index]}"

    export CLUSTER="$cluster"
    envsubst <"$MANIFESTS_DIR/namespace.yaml" |
      kubectl --context "$context" apply -f -

    kubectl create secret generic cacerts -n istio-system \
      --from-file="$CERT_DIR/$cluster/ca-cert.pem" \
      --from-file="$CERT_DIR/$cluster/ca-key.pem" \
      --from-file="$CERT_DIR/root-cert.pem" \
      --from-file="$CERT_DIR/$cluster/cert-chain.pem" \
      --dry-run=client -o yaml |
      kubectl --context "$context" -n istio-system apply -f -

    envsubst <"$MANIFESTS_DIR/controlplane.yaml" |
      istioctl install \
        --context "$context" \
        -y -f -

    envsubst <"$MANIFESTS_DIR/eastwest-gateway.yaml" |
      istioctl install \
        --context "$context" \
        -y -f -

    kubectl --context "$context" apply -n istio-system -f "$MANIFESTS_DIR/expose-services.yaml"

    ip="$(
      kubectl --context "$context" get node "$cluster-control-plane" -o yaml |
        yq '.status.addresses.[] | select(.type == "InternalIP") | .address'
    )"

    kubectl patch service istio-eastwestgateway \
      --context "$context" \
      --patch "{\"spec\": {\"externalIPs\": [\"${ip}\"]}}" \
      -n istio-system

    for other_cluster_index in "${!CONTEXTS[@]}"; do
      local other_cluster="${CLUSTERS[$other_cluster_index]}"
      local other_context="${CONTEXTS[$other_cluster_index]}"

      if [ "$other_cluster" != "${cluster}" ]; then
        istioctl \
          --context "$other_context" create-remote-secret \
          --name="cluster-$other_cluster" |
          kubectl \
            --context "${context}" apply -f -
      fi
    done
  done
}

prepare_certs
install
