#!/bin/bash
#
# Create the kind clusters and install basic dependencies
#

set -eu -o pipefail

source ".env"

create_cluster() {
  local -r cluster_index=$1
  local -r kubernetes_version=$2

  local -r cluster="${CLUSTERS[$cluster_index]}"

  kind get clusters | grep "$cluster" >/dev/null ||
    kind create cluster \
      --name "$cluster" \
      --image "kindest/node:$kubernetes_version" \
      --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  podSubnet: "${CLUSTER_POD_CIDRS[$cluster_index]}"
  serviceSubnet: "${CLUSTER_SVC_CIDRS[$cluster_index]}"
nodes:
- role: control-plane
$(for _ in $(seq 1 $((CLUSTER_NODE_COUNTS[cluster_index] - 1))); do echo "- role: worker"; done)
EOF

  # use control plane node ip instead of default localhost so that the kubeconfig can be use by admiralty for inter
  # cluster authentication
  ip="$(
    kubectl --context "kind-$cluster" get node "$cluster-control-plane" -o yaml |
      yq '.status.addresses.[] | select(.type == "InternalIP") | .address'
  )"
  yq -i ".clusters |= map(select(.name == \"kind-$cluster\").cluster.server = \"https://$ip:6443\")" ~/.kube/config
}

install_dependencies() {
  local -r context=$1

  echo "Installing dependencies on cluster $context..."

  helmfile init >/dev/null
  KUBECONTEXT=$context helmfile apply \
    --kube-context "$context" \
    --wait
}

for cluster_index in "${!CLUSTERS[@]}"; do
  create_cluster "$cluster_index" "$KUBERNETES_VERSION"
done

# TODO: add basic network test between clusters
for context in "${CONTEXTS[@]}"; do
  install_dependencies "$context" || true
done
