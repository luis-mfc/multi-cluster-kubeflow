#!/bin/bash

# Exit on error
set -eu -o pipefail

source "$(dirname $0)/../../.env"

management_cluster="${CLUSTERS[0]}"

kubectl \
  --context "kind-$management_cluster" \
  label ns default "multicluster-scheduler=enabled"

for i in $(seq 1 10); do
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
        # https://github.com/admiraltyio/admiralty/issues/201#issuecomment-1861798315
        multicluster.admiralty.io/no-reservation: ""
        multicluster.admiralty.io/use-constraints-from-spec-for-proxy-pod-scheduling: ""
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 1
              preference:
                matchExpressions:
                - key: multicluster.admiralty.io/cluster-target-name
                  operator: In
                  values:
                  - dc
      containers:
      - name: c
        image: busybox
        command: ["sh", "-exc", "echo Processing item $i && sleep 5"]
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
