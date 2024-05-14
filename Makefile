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
	./scripts/admiralty/up.sh

down stop: ## Stop env
	./scripts/admiralty/down.sh

test: ## Test
	./scripts/admiralty/test.sh
