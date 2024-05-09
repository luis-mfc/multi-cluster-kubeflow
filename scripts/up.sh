#!/bin/bash

# Exit on error
set -eu

source "$(dirname $0)/../.env"

create_cluster() {
    local profile=$1
    local namespace=$2
    local kubernetes_version=$3

    set -x
    minikube status -p "$profile" >/dev/null 2>&1 || minikube start \
        -p "$profile" \
        --namespace "$namespace" \
        --kubernetes-version "$kubernetes_version"
    set +x
}

for cluster in "${CLUSTERS[@]}"
do
    create_cluster "$cluster" "$cluster" "$KUBERNETES_VERSION" 
done
