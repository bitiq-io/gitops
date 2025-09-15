SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

CHARTS := charts/bootstrap-operators charts/argocd-apps charts/bitiq-umbrella charts/image-updater charts/ci-pipelines charts/bitiq-sample-app

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

lint: ## helm lint all charts
	@for c in $(CHARTS); do \
	  echo "==> helm lint $$c"; \
	  if [ "$$c" = "charts/bitiq-sample-app" ]; then \
	    helm lint $$c -f $$c/values-common.yaml -f $$c/values-local.yaml || exit 1; \
	  else \
	    helm lint $$c || exit 1; \
	  fi; \
	done

template: ## helm template sanity (local, sno, prod)
	@for env in local sno prod; do \
	  echo "==> argocd-apps ($$env)"; \
	  helm template charts/argocd-apps --set envFilter=$$env >/dev/null || exit 1; \
	done

validate: ## run full validation (lint, render, schema, policy)
	@bash scripts/validate.sh

smoke: ## run cluster smoke checks (ENV=<env> [BOOTSTRAP=true] [BASE_DOMAIN=...])
	@ENV=${ENV} BOOTSTRAP=${BOOTSTRAP} BASE_DOMAIN=${BASE_DOMAIN} bash scripts/smoke.sh ${ENV}

dev-setup: ## install local commit-msg hook (requires Node/npm)
	@bash scripts/dev-setup.sh
