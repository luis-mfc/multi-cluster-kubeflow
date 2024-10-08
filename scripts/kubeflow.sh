#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname "$0")/../.env"

MANIFESTS_DIR="$(dirname "$0")/../manifests/kubeflow"

# TODO: tmp workaround for istio setup
remove_kubeflow_health_checks() {
  cluster=$1

  IFS=' ' read -ra deployments <<<"$(kubectl --context "kind-$cluster" get deployments -n kubeflow -o jsonpath='{.items[*].metadata.name}')"
  for deployment in "${deployments[@]}"; do
    kubectl --context "kind-$cluster" get deploy "$deployment" -n kubeflow -o yaml |
      yq '.spec.template.spec.containers |= map(select(.livenessProbe != null).livenessProbe = null)' |
      yq '.spec.template.spec.containers |= map(select(.readinessProbe != null).readinessProbe = null)' |
      kubectl --context "kind-$cluster" apply -f -
  done
}

cp "$MANIFESTS_DIR/kubeflow.yaml" .kubeflow/example/kustomization.yaml
cd .kubeflow && while ! kustomize build example | kubectl apply --context "kind-dc" -f -; do echo "Retrying to apply resources"; sleep 10; done
cd ..

while ! remove_kubeflow_health_checks "dc"; do echo "Retrying to apply health check hack"; sleep 1; done


cp "$MANIFESTS_DIR/kubeflow-workloads.yaml" .kubeflow/example/kustomization.yaml
cd .kubeflow && while ! kustomize build example | kubectl apply --context "kind-aws" -f -; do echo "Retrying to apply resources"; sleep 10; done
cd ..

while ! remove_kubeflow_health_checks "dc"; do echo "Retrying to apply health check hack"; sleep 1; done
