#!/bin/bash

set -eu -o pipefail

error_if_not_installed() {
  program_name=$1

  if ! command -v "$program_name" >/dev/null; then
    echo -e "\033[31mDependency '$program_name' not found"
  fi
}

declare -a dependencies=("kind" "kubectl" "helm" "helmfile" "step" "istioctl")
for dependency in "${dependencies[@]}"; do
  error_if_not_installed "$dependency"
done

if ! istioctl version | grep -q "$ISTIOCTL_VERSION" ; then
  # shellcheck disable=SC2028
  echo -e "\033[31m istioctl installed, but version does not match '$ISTIOCTL_VERSION'\033[0m"
  exit 1
fi
