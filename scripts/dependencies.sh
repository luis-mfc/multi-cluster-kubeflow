#!/bin/bash

set -eu -o pipefail

error_if_not_installed() {
  local -r program_name=$1

  if ! command -v "$program_name" >/dev/null; then
    echo -e "\033[31mDependency '$program_name' not found\033[0m"
    exit 1
  fi
}

declare -a dependencies=("kind" "kubectl" "helm" "helmfile" "step" "istioctl" "yq" "jq")
for dependency in "${dependencies[@]}"; do
  error_if_not_installed "$dependency"
done
