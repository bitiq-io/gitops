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

quay-secret: ## create/link Quay push secret for pipeline SA (QUAY_USERNAME, QUAY_PASSWORD, QUAY_EMAIL required)
	@if [ -z "$$QUAY_USERNAME" ] || [ -z "$$QUAY_PASSWORD" ] || [ -z "$$QUAY_EMAIL" ]; then \
	  echo "Set QUAY_USERNAME, QUAY_PASSWORD, QUAY_EMAIL"; exit 1; \
	fi
	@oc -n openshift-pipelines create secret docker-registry quay-auth \
	  --docker-server=quay.io \
	  --docker-username="$$QUAY_USERNAME" \
	  --docker-password="$$QUAY_PASSWORD" \
	  --docker-email="$$QUAY_EMAIL" \
	  --dry-run=client -o yaml | oc apply -f -
	@oc -n openshift-pipelines annotate secret quay-auth tekton.dev/docker-0=https://quay.io --overwrite >/dev/null 2>&1 || true
	@oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount >/dev/null 2>&1 || true
	@echo "Quay secret configured and linked to SA 'pipeline'"

image-updater-secret: ## create/update argocd-image-updater-secret from ARGOCD_TOKEN (and restart deployment)
	@if [ -z "$$ARGOCD_TOKEN" ]; then \
	  echo "Set ARGOCD_TOKEN environment variable"; exit 1; \
	fi
	@oc -n openshift-gitops get ns >/dev/null 2>&1 || { echo "Namespace openshift-gitops not found"; exit 1; }
	@echo "Applying argocd-image-updater-secret in openshift-gitops"
	@oc -n openshift-gitops create secret generic argocd-image-updater-secret \
	  --from-literal=argocd.token="$$ARGOCD_TOKEN" --dry-run=client -o yaml | oc apply -f -
	@oc -n openshift-gitops rollout restart deploy/argocd-image-updater >/dev/null 2>&1 || true
dev-setup: ## install local commit-msg hook (requires Node/npm)
	@bash scripts/dev-setup.sh
