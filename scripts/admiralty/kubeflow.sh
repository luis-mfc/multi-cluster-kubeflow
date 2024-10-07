#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../../.env"

# TODO: tmp workaround
remove_kubeflow_health_checks() {
  cluster=$1

  IFS=' ' read -a deployments <<<"$(kubectl --context "kind-$cluster" get deployments -n kubeflow -o jsonpath='{.items[*].metadata.name}')"
  for deployment in "${deployments[@]}"; do
    kubectl --context "kind-$cluster" get deploy "$deployment" -n kubeflow -o yaml | yq '.spec.template.spec.containers |= map(select(.livenessProbe != null).livenessProbe = null)' | kubectl --context "kind-$cluster" apply -f -
    kubectl --context "kind-$cluster" get deploy "$deployment" -n kubeflow -o yaml | yq '.spec.template.spec.containers |= map(select(.readinessProbe != null).readinessProbe = null)' | kubectl --context "kind-$cluster" apply -f -
  done
}

for cluster in "${CLUSTERS[@]}"; do
  while ! remove_kubeflow_health_checks "$cluster"; do echo "Retrying to apply resources on $cluster"; sleep 1; done
done
