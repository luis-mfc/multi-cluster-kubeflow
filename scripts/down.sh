#!/bin/bash
#
# Destroy the kind clusters
#

set -eu -o pipefail

source ".env"

delete_cluster() {
  local -r cluster=$1

  kind delete cluster --name "$cluster"
}

for cluster in "${CLUSTERS[@]}"; do
  delete_cluster "$cluster" || true
done
