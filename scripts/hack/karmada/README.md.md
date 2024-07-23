# Setup
1. prerequisites:
```shell
if ! command -v karmadactl &> /dev/null; then
  curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh |
    sudo INSTALL_CLI_VERSION=1.10.3 bash
fi
```
2. clusters
```shell
# make up
./scripts/hack/karmada kind-aws $HOME/.kube/kind-aws.config
./scripts/hack kind-dc $HOME/.kube/kind-dc.config
```
3. Install Karmada on mgmt cluster:
```shell
karmadactl init \
  --kubeconfig=$HOME/.kube/kind-aws.config \
  --karmada-data scripts/hack/karmada/data \
  --karmada-pki scripts/hack/karmada/pki
```
4. Register workload cluster:
```shell
karmadactl \
  --kubeconfig scripts/hack/karmada/data/karmada-apiserver.config join kind-dc \
  --cluster-kubeconfig=$HOME/.kube/kind-dc.config
```
5. Scheduling configuration:
```shell
# https://karmada.io/docs/userguide/scheduling/resource-propagating#configure-explicit-priority
cat <<EOF | kubectl apply --kubeconfig scripts/hack/karmada/data/karmada-apiserver.config -f -
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: propagation-high-explicit-priority
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      labelSelector:
        matchLabels:
          app: nginx
  priority: 2
  placement:
    clusterAffinity:
      clusterNames:
        - kind-dc
---
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: propagation-low-explicit-priority
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      labelSelector:
        matchLabels:
          app: nginx
  priority: 1
  placement:
    clusterAffinity:
      clusterNames:
        - kind-aws
EOF
cat <<EOF | kubectl apply --kubeconfig scripts/hack/karmada/data/karmada-apiserver.config -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "1Gi"
            cpu: "1"
          limits:
            memory: "1Gi"
EOF
```


