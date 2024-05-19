#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../.env"

create_cluster() {
  local cluster=$1
  local kubernetes_version=$2

  kind get clusters | grep "$cluster" >/dev/null || kind create cluster \
    --name "$cluster" \
    --image "kindest/node:$kubernetes_version"
}

for cluster in "${CLUSTERS[@]}"; do
  create_cluster "$cluster" "$KUBERNETES_VERSION"
done
