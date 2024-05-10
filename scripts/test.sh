#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../.env"

management_cluster="${CLUSTERS[0]}"

kubectl \
  --context "kind-$management_cluster" \
  label ns default "multicluster-scheduler=enabled"

for i in $(seq 1 5); do
  cat <<EOF | kubectl --context "kind-$management_cluster" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: global-$i
spec:
  ttlSecondsAfterFinished: 10
  template:
    metadata:
      annotations:
        multicluster.admiralty.io/elect: ""
    spec:
      containers:
      - name: c
        image: busybox
        command: ["sh", "-c", "echo Processing item $i && sleep 5"]
        resources:
          requests:
            cpu: 100m
      restartPolicy: Never
EOF
done

while true; do
  clear

  for cluster in "${CLUSTERS[@]}"; do
    kubectl --context "kind-$cluster" get pods -o wide
  done
  sleep 2
done
