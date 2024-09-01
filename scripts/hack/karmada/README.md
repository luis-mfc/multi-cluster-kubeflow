# Setup
1. prerequisites:
```shell
if ! command -v karmadactl &> /dev/null; then
  curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh |
    sudo INSTALL_CLI_VERSION=1.11.0 bash
fi
export KARMADA_REPO=scripts/hack/karmada/upstream-karmada
[[ -d "$KARMADA_REPO" ]] || git clone git@github.com:karmada-io/karmada.git -b v1.11.0 "$KARMADA_REPO"
```
2. clusters
```shell
$KARMADA_REPO/hack/create-cluster.sh kind-karmada $HOME/.kube/kind-karmada.config
$KARMADA_REPO/hack/create-cluster.sh kind-aws $HOME/.kube/kind-aws.config
$KARMADA_REPO/hack/create-cluster.sh kind-dc $HOME/.kube/kind-dc.config
```
3. Install Karmada on mgmt cluster:
```shell
karmadactl init \
  --kubeconfig=$HOME/.kube/kind-karmada.config \
  --karmada-data scripts/hack/karmada/data \
  --karmada-pki scripts/hack/karmada/pki
```
4. Register workload cluster:
```shell
karmadactl \
  --kubeconfig scripts/hack/karmada/data/karmada-apiserver.config join kind-aws \
  --cluster-kubeconfig=$HOME/.kube/kind-aws.config
karmadactl \
  --kubeconfig scripts/hack/karmada/data/karmada-apiserver.config join kind-dc \
  --cluster-kubeconfig=$HOME/.kube/kind-dc.config
```
5. Scheduling configuration:
```shell
# https://karmada.io/docs/userguide/scheduling/resource-propagating#configure-explicit-priority
kubectl apply --kubeconfig scripts/hack/karmada/data/karmada-apiserver.config -f - <<EOF 
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
  priority: 1
  placement:
    clusterAffinity:
      clusterNames:
        - kind-aws
        - kind-dc
EOF
kubectl apply --kubeconfig scripts/hack/karmada/data/karmada-apiserver.config -f - <<EOF 
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
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
6. Destroy:
```shell
kind delete cluster --name kind-karmada
kind delete cluster --name kind-aws
kind delete cluster --name kind-dc
rm ~/.kube/kind-*
rm -r scripts/hack/karmada/data
```
---
# Setup via scripts
1. clusters
```shell
export MEMBER_CLUSTER_1_NAME="kind-dc"
export MEMBER_CLUSTER_2_NAME="kind-aws"
./local-up-karmada.sh
export KUBECONFIG=~/.kube/karmada.config
kubectl config use-context karmada-apiserver
```
2. Scheduling configuration:
```shell
# https://karmada.io/docs/userguide/scheduling/resource-propagating#configure-explicit-priority
kubectl apply -f - <<EOF
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: nginx-propagation
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      labelSelector:
        matchLabels:
          app: nginx
  placement:
    clusterAffinity:
      clusterNames:
        - kind-dc
        - member3
EOF
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
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
