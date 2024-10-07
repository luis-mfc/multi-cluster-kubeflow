#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../../.env"

management_cluster="${CLUSTERS[0]}"

kubectl \
  --context "kind-$management_cluster" \
  label ns default "multicluster-scheduler=enabled"

for i in $(seq 1 3); do
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
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 1
              preference:
                matchExpressions:
                - key: topology.kubernetes.io/region
                  operator: In
                  values:
                  - dc
      containers:
      - name: c
        image: busybox
        command: ["sh", "-c", "echo Processing item $i && sleep 30"]
        resources:
          requests:
            cpu: 8
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
