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
install_kubeflow "$CLOUD_CLUSTER_CONTEXT" "$MANIFESTS_DIR/kubeflow-cloud.yaml"

rm -rf .kubeflow
