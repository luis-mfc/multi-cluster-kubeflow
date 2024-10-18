#!/bin/bash

set -eu -o pipefail

source "$(dirname "$0")/../.env"

MANIFESTS_DIR="$(dirname "$0")/../manifests/kubeflow"

# TODO: tmp workaround for istio setup
remove_kubeflow_health_checks() {
  cluster=$1

  IFS=' ' read -ra deployments <<<"$(kubectl --context "$cluster" get deployments -n kubeflow -o jsonpath='{.items[*].metadata.name}')"
  for deployment in "${deployments[@]}"; do
    kubectl --context "$cluster" get deploy "$deployment" -n kubeflow -o yaml |
      yq '.spec.template.spec.containers |= map(select(.livenessProbe != null).livenessProbe = null)' |
      yq '.spec.template.spec.containers |= map(select(.readinessProbe != null).readinessProbe = null)' |
      kubectl --context "$cluster" apply -f -
  done
}

([ ! -d "kubeflow" ] && git clone -b "$KUBEFLOW_VERSION" https://github.com/kubeflow/manifests.git .kubeflow) || true

cp "$MANIFESTS_DIR/kubeflow.yaml" .kubeflow/example/kustomization.yaml
cd .kubeflow && while ! kustomize build example | kubectl apply --context "$DC_CLUSTER_CONTEXT" -f -; do echo "Retrying to apply resources"; sleep 10; done
cd ..
while ! remove_kubeflow_health_checks "$DC_CLUSTER_CONTEXT"; do echo "Retrying to apply health check hack"; sleep 1; done


cp "$MANIFESTS_DIR/kubeflow-cloud.yaml" .kubeflow/example/kustomization.yaml
cd .kubeflow && while ! kustomize build example | kubectl apply --context "$CLOUD_CLUSTER_CONTEXT" -f -; do echo "Retrying to apply resources"; sleep 10; done
cd ..
while ! remove_kubeflow_health_checks "$CLOUD_CLUSTER_CONTEXT"; do echo "Retrying to apply health check hack"; sleep 1; done

rm -rf .kubeflow
