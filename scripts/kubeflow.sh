#!/bin/bash
#
# Install kubeflow based using the upstream documentation:
#   - https://github.com/kubeflow/manifests/tree/v1.8.1?tab=readme-ov-file#install-with-a-single-command
#

set -eu -o pipefail

source ".env"

MANIFESTS_DIR="$(dirname "$0")/../manifests/kubeflow"

remove_kubeflow_health_checks() {
  local -r cluster=$1

  IFS=' ' read -ra deployments <<<"$(kubectl --context "$cluster" get deployments -n kubeflow -o jsonpath='{.items[*].metadata.name}')"
  for deployment in "${deployments[@]}"; do
    kubectl --context "$cluster" get deploy "$deployment" -n kubeflow -o yaml |
      yq '.spec.template.spec.containers |= map(select(.livenessProbe != null).livenessProbe = null)' |
      yq '.spec.template.spec.containers |= map(select(.readinessProbe != null).readinessProbe = null)' |
      kubectl --context "$cluster" apply -f -
  done
}

install_kubeflow() {
  local -r context=$1
  local -r kustomization_file=$2

  cp "$kustomization_file" .kubeflow/example/kustomization.yaml
  cd .kubeflow && while ! kustomize build example | kubectl apply --context "$context" -f -; do
    echo "Retrying to apply resources"
    sleep 10
  done
  cd ..

  # TODO: tmp workaround for istio setup
  while ! remove_kubeflow_health_checks "$context"; do
    echo "Retrying to apply health check hack"
    sleep 1
  done

}

([ ! -d "kubeflow" ] && git clone -b "$KUBEFLOW_VERSION" https://github.com/kubeflow/manifests.git .kubeflow) || true

install_kubeflow "$DC_CLUSTER_CONTEXT" "$MANIFESTS_DIR/kubeflow.yaml"
# kubectl --context "$DC_CLUSTER_CONTEXT" apply -f - <<EOF
# apiVersion: v1
# kind: ConfigMap
# metadata:
#   name: istio
#   namespace: istio-system
# data:
#   mesh: |-
#     accessLogFile: /dev/stdout
#     defaultConfig:
#       discoveryAddress: istiod.istio-system.svc:15012
#       proxyMetadata: {}
#       tracing: {}
#     enablePrometheusMerge: true
#     rootNamespace: istio-system
#     tcpKeepalive:
#       interval: 5s
#       probes: 3
#       time: 10s
#     trustDomain: cluster.local
#     extensionProviders:
#     - envoyExtAuthzHttp:
#         headersToDownstreamOnDeny:
#         - content-type
#         - set-cookie
#         headersToUpstreamOnAllow:
#         - authorization
#         - path
#         - x-auth-request-email
#         - x-auth-request-groups
#         - x-auth-request-user
#         includeRequestHeadersInCheck:
#         - authorization
#         - cookie
#         service: oauth2-proxy.oauth2-proxy.svc.cluster.local
#         port: 80
#       name: oauth2-proxy
# EOF
install_kubeflow "$CLOUD_CLUSTER_CONTEXT" "$MANIFESTS_DIR/kubeflow-cloud.yaml"

rm -rf .kubeflow
