#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname "$0")/../.env"

CERT_DIR=".certs"
MANIFESTS_DIR="$(dirname "$0")/../manifests/istio"

# https://itnext.io/istio-multi-cluster-setup-b773313c074a

error_if_not_installed() {
  program_name=$1

  if ! command -v "$program_name" >/dev/null; then
    echo "$program_name missing: https://smallstep.com/docs/step-cli/installation/#debian-ubuntu"
  fi
}

# Certificates
prepare_certs() {

  echo "Clean up contents of dir './chapter12/certs'"
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
  for cluster in "${CLUSTERS[@]}"; do

    export CLUSTER="$cluster"

    envsubst <"$MANIFESTS_DIR/namespace.yaml" |
      kubectl --context="kind-$cluster" apply -f -

    kubectl create secret generic cacerts -n istio-system \
      --from-file="$CERT_DIR/$cluster/ca-cert.pem" \
      --from-file="$CERT_DIR/$cluster/ca-key.pem" \
      --from-file="$CERT_DIR/root-cert.pem" \
      --from-file="$CERT_DIR/$cluster/cert-chain.pem" \
      --dry-run=client -o yaml |
      kubectl --context="kind-$cluster" -n istio-system apply -f -

    envsubst <"$MANIFESTS_DIR/controlplane.yaml" |
      istioctl install \
        --context="kind-$cluster" \
        -y -f -

    envsubst <"$MANIFESTS_DIR/eastwest-gateway.yaml" |
      istioctl install \
        --context="kind-$cluster" \
        -y -f -

    kubectl --context="kind-$cluster" apply -n istio-system -f "$MANIFESTS_DIR/expose-services.yaml"

    ip="$(
      kubectl --context="kind-$cluster" get node "$cluster-control-plane" -o yaml |
        yq '.status.addresses.[] | select(.type == "InternalIP") | .address'
    )"

    kubectl patch service istio-eastwestgateway \
      --context="kind-$cluster" \
      --patch "{\"spec\": {\"externalIPs\": [\"${ip}\"]}}" \
      -n istio-system

    for other_cluster in "${CLUSTERS[@]}"; do
      if [ "$other_cluster" != "${cluster}" ]; then
        istioctl \
          --context="kind-$other_cluster" x create-remote-secret \
          --name="cluster-$other_cluster" |
          kubectl \
            --context="kind-${cluster}" apply -f -
      fi
    done
  done
}

declare -a dependencies=("step" "istioctl")
for dependency in "${dependencies[@]}"; do
  error_if_not_installed "$dependency"
done

prepare_certs
install

test() {
  kubectl --context=kind-dc create ns test || true
  kubectl --context=kind-aws create ns test || true

  kubectl --context=kind-dc label namespace test istio-injection=enabled --overwrite
  kubectl --context=kind-aws label namespace test istio-injection=enabled --overwrite

  kubectl --context=kind-dc apply -n test -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox
spec:
  replicas: 1
  selector:
    matchLabels:
      app: busybox
  template:
    metadata:
      labels:
        app: busybox
    spec:
      containers:
      - name: busybox
        image: busybox
        command:
          - sleep
          - inf
        ports:
        - containerPort: 80
EOF

  kubectl --context=kind-aws apply -n test -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
EOF
  kubectl --context kind-dc wait -n test --for=condition=ready pod -l app=busybox
  kubectl --context kind-aws wait -n test --for=condition=ready pod -l app=nginx
  kubectl --context kind-dc exec -n test deploy/busybox -- wget -O- http://nginx:80
}

# shellcheck disable=SC2028
test || echo "\033[0;31m basic istio testing failed"
