#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../.env"

create_cluster() {
  local cluster_index=$1
  local kubernetes_version=$2

  local -r cluster="${CLUSTERS[$cluster_index]}"

  kind get clusters | grep "$cluster" >/dev/null || kind create cluster \
    --name "$cluster" \
    --image "kindest/node:$kubernetes_version" \
    --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  podSubnet: "${CLUSTER_POD_CIDRS[$cluster_index]}"
EOF

  ip="$(
      kubectl --context="kind-$cluster" get node "$cluster-control-plane" -o yaml |
        yq '.status.addresses.[] | select(.type == "InternalIP") | .address'
    )"
  yq -i ".clusters |= map(select(.name == \"kind-$cluster\").cluster.server = \"https://$ip:6443\")" ~/.kube/config
}

for cluster_index in "${!CLUSTERS[@]}"; do
  create_cluster "$cluster_index" "$KUBERNETES_VERSION"
done
