include .hashes/hashdeps.mk

UV=.tmp/bin/uv
IMAGE=docker.io/library/dunamai
DOCKER=docker

$(UV):
	mkdir -p `dirname $@`
	export CARGO_HOME=`pwd`/.tmp && cd .tmp && wget -O install.sh https://astral.sh/uv/install.sh && chmod +x install.sh && ./install.sh --no-modify-path && rm -f install.sh

.PHONY: install
install: .venv/status ## Install the virtual env

.PHONY: build
build: uv.lock ## Build the docker image (locally)
	$(DOCKER) build -t $(IMAGE) .

.PHONY: _version
_version: .venv/status
	@$(UV) run dunamai from any --style semver |sed "s/+/_/g"

version:
	@$(MAKE) -s _version 2>&1 |tail -1

test: build ## Test the docker image (locally)
	$(DOCKER) run --rm -v `pwd`:/code $(IMAGE) from git --path /code
	@echo "OK"

uv.lock: $(call hash_deps,pyproject.toml)
	$(UV) lock

.venv/status: $(UV) $(call hash_deps,uv.lock)
	$(UV) sync --frozen
	touch $@

.PHONY: clean
clean: ## Clean the repository
	rm -Rf .tmp .venv

.PHONY: no-dirty
no-dirty: ## Test if there are some dirty files
	@if test -n "$$(git status --porcelain)"; then \
		echo "ERROR: the repository is dirty"; \
		git status; \
		git diff; \
		exit 1; \
	fi

.PHONY: help
help:
	@# See https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
