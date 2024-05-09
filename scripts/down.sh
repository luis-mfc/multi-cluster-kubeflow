#!/bin/bash

set -u

source "$(dirname $0)/../.env"

delete_cluster() {
  local profile=$1

  minikube delete \
    -p "$profile"
}

for cluster in "${CLUSTERS[@]}"; do
  delete_cluster "$cluster" || true
done
