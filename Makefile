#!make
SHELL := /bin/sh -eu

include .env
export

# self documenting makefile, fetches lines marked with target description (2 '#'s)
help: ## Show this help message
	@grep -E '^[a-zA-Z _-]+: ?## .*$$' $(MAKEFILE_LIST) | \
		sed 's/##//g' | \
		awk -F ':' '{printf "%s \n %s\n\n", $$2, $$3}'

up start: ## Start env
	./scripts/up.sh

# kubeflow:
# 	kubectl config use-context aws
# 	@if [ ! -d ".kubeflow" ]; then \
# 		git clone -b v1.7.0 https://github.com/kubeflow/manifests.git .kubeflow ; \
# 	fi

# 	cp deployments/manifests/kubeflow/example/kustomization.yaml .kubeflow/example/kustomization.yaml
# 	cp deployments/manifests/kubeflow/spawner_ui_config.yaml .kubeflow/apps/jupyter/jupyter-web-app/upstream/base/configs/spawner_ui_config.yaml
# 	cp deployments/manifests/kubeflow/dashboard_config.yaml .kubeflow/apps/centraldashboard/upstream/base/configmap.yaml
# 	cp deployments/manifests/kubeflow/dashboard_config.yaml .kubeflow/apps/centraldashboard/upstream/overlays/kserve/patches/configmap.yaml

# 	cd .kubeflow && while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done
# 	cd ..
# 	rm -rf .kubeflow

admiralty:
	for CLUSTER_NAME in $$CLUSTERS; do \
		echo $$CLUSTER_NAME; \
	done

down stop: ## Stop env
	./scripts/down.sh