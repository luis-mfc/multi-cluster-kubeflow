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
  cp "$MANIFESTS_DIR/dashboard-ui.yaml" .kubeflow/apps/centraldashboard/upstream/overlays/kserve/patches/configmap.yaml
  envsubst < "$MANIFESTS_DIR/spawner_ui_config.yaml" > .kubeflow/apps/jupyter/jupyter-web-app/upstream/base/configs/spawner_ui_config.yaml

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

configure_admiralty() {
  namespace=$1
  context=$2

  # kubeflow may take a while to provision the ns
  echo "Waiting for namespace $namespace to be created in context $DC_CLUSTER_NAME..."
  while ! kubectl --context "$context" get namespace "$namespace" >/dev/null 2>&1; do
    sleep 1
  done

  kubectl \
    --context "$context" \
    label ns "$namespace" "multicluster-scheduler=enabled"

  # add admiralty annotations to the notebook pods as well as DC cluster preferred affinity
  # (not so important in this poc scenario)
  kubectl apply --context "$context" -f - <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-annotation-to-pods
  annotations:
    policies.kyverno.io/title: Add Annotation to Pods
    policies.kyverno.io/category: Pod Management
    policies.kyverno.io/severity: low
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Adds a custom annotation to all pods in the specified namespace.
spec:
  rules:
  - name: add-annotation
    match:
      any:
      - resources:
          kinds:
            - Pod
          namespaces:
            - $namespace
    mutate:
      patchStrategicMerge:
        # required admiralty annotations
        metadata:
          annotations:
            multicluster.admiralty.io/elect: ""
            multicluster.admiralty.io/no-reservation: ""
            multicluster.admiralty.io/use-constraints-from-spec-for-proxy-pod-scheduling: ""
        # required admiralty annotations
        spec:
          affinity:
            nodeAffinity:
              preferredDuringSchedulingIgnoredDuringExecution:
                - weight: 1
                  preference:
                    matchExpressions:
                    - key: multicluster.admiralty.io/cluster-target-name
                      operator: In
                      values:
                        - $DC_CLUSTER_NAME
EOF
}

([ ! -d "kubeflow" ] && git clone -b "$KUBEFLOW_VERSION" https://github.com/kubeflow/manifests.git .kubeflow) || true

install_kubeflow "$DC_CLUSTER_CONTEXT" "$MANIFESTS_DIR/kubeflow.yaml"
install_kubeflow "$CLOUD_CLUSTER_CONTEXT" "$MANIFESTS_DIR/kubeflow-cloud.yaml"
configure_admiralty "kubeflow-user-example-com" "$DC_CLUSTER_CONTEXT"

rm -rf .kubeflow
