#!make
SHELL := /bin/sh -eu

include .env
export

# self documenting makefile, fetches lines marked with target description (2 '#'s)
help: ## Show this help message
	@grep -E '^[a-zA-Z _-]+: ?## .*$$' $(MAKEFILE_LIST) | \
		sed 's/##//g' | \
		awk -F ':' '{printf "%s \n %s\n\n", $$2, $$3}'

dependencies: ## Start env
	#https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files
	sudo sysctl fs.inotify.max_user_instances=2280 && \
		sudo sysctl fs.inotify.max_user_watches=1255360
	./scripts/dependencies.sh

up start: dependencies ## Start env
	./scripts/up.sh
	./scripts/scheduling.sh
	k config use-context $$DC_CLUSTER_CONTEXT

down stop: ## Stop env
	./scripts/down.sh

kubeflow: ## Install Kubeflow
	./scripts/istio.sh
	./scripts/kubeflow.sh

	kubectl wait deployment/istio-ingressgateway \
		--for=condition=available \
		--timeout=600s \
		--context $$DC_CLUSTER_CONTEXT \
		-n istio-system
	kubectl port-forward svc/istio-ingressgateway 8080:80 \
		--context $$DC_CLUSTER_CONTEXT \
		-n istio-system

test: ## Test
	./scripts/test.sh

all: up kubeflow ## create kubeflow environment
