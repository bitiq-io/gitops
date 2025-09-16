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

tekton-setup: ## create image ns + grant pusher; create webhook secret if GITHUB_WEBHOOK_SECRET is set
	@oc new-project bitiq-ci >/dev/null 2>&1 || true
	@oc policy add-role-to-user system:image-pusher system:serviceaccount:openshift-pipelines:pipeline -n bitiq-ci >/dev/null 2>&1 || true
	@if [ -n "$$GITHUB_WEBHOOK_SECRET" ]; then \
	  echo "Creating GitHub webhook secret in openshift-pipelines"; \
	  oc -n openshift-pipelines create secret generic github-webhook-secret \
	    --from-literal=secretToken="$$GITHUB_WEBHOOK_SECRET" >/dev/null 2>&1 || \
	    oc -n openshift-pipelines set data secret/github-webhook-secret secretToken="$$GITHUB_WEBHOOK_SECRET" >/dev/null 2>&1 || true; \
	else \
	  echo "Set GITHUB_WEBHOOK_SECRET to create webhook secret"; \
	fi

dev-setup: ## install local commit-msg hook (requires Node/npm)
	@bash scripts/dev-setup.sh
