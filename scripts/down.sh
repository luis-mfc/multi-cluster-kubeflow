#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../.env"

delete_cluster() {
  local cluster=$1

  kind delete cluster --name "$cluster"
}

for cluster in "${CLUSTERS[@]}"; do
  delete_cluster "$cluster" || true
done
