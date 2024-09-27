#!make
SHELL := /bin/sh -eu

include .env
export

# self documenting makefile, fetches lines marked with target description (2 '#'s)
help: ## Show this help message
	@grep -E '^[a-zA-Z _-]+: ?## .*$$' $(MAKEFILE_LIST) | \
		sed 's/##//g' | \
		awk -F ':' '{printf "%s \n %s\n\n", $$2, $$3}'
		
create: ## Create the 2 bare clusters
	sudo sysctl fs.inotify.max_user_instances=2280
	sudo sysctl fs.inotify.max_user_watches=1255360
	./scripts/create.sh

up start: create ## Start env
	./scripts/create.sh
	./scripts/$$TOOL/up.sh

down stop: ## Stop env
	./scripts/down.sh

kubeflow: ## Install Kubeflow
	@([ ! -d "kubeflow" ] && git clone -b v1.8.1 https://github.com/kubeflow/manifests.git .kubeflow) || true

	# aws
	cp kubeflow.yaml .kubeflow/example/kustomization.yaml
	cd .kubeflow && while ! kustomize build example | kubectl apply --context kind-aws -f -; do echo "Retrying to apply resources"; sleep 10; done
	cd ..

	# dc
	cp kubeflow-workloads.yaml .kubeflow/example/kustomization.yaml
	cd .kubeflow && while ! kustomize build example | kubectl apply --context kind-dc -f -; do echo "Retrying to apply resources"; sleep 10; done
	cd ..

	rm -rf .kubeflow
	./scripts/$$TOOL/kubeflow.sh
	kubectl wait --for=condition=available --timeout=600s --context kind-aws deployment/istio-ingressgateway -n istio-system
	kubectl port-forward --context kind-aws svc/istio-ingressgateway -n istio-system 8080:80

test: ## Test
	./scripts/$$TOOL/test.sh

all: up kubeflow ## create env
