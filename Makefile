SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

CHARTS := charts/bootstrap-operators charts/argocd-apps charts/bitiq-umbrella charts/image-updater charts/ci-pipelines charts/toy-service charts/toy-web charts/eso-vault-examples

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

lint: ## helm lint all charts
	@for c in $(CHARTS); do \
	  echo "==> helm lint $$c"; \
	  if [ "$$c" = "charts/toy-service" ] || [ "$$c" = "charts/toy-web" ]; then \
	    helm lint $$c -f $$c/values-common.yaml -f $$c/values-local.yaml || exit 1; \
	  else \
	    helm lint $$c || exit 1; \
	  fi; \
	done

hu: ## run helm-unittest suites (requires helm-unittest plugin)
	@for c in $(CHARTS); do \
	  if [ -d "$$c/tests" ]; then \
	    echo "==> helm unittest $$c"; \
	    helm unittest $$c || exit 1; \
	  fi; \
	done

template: ## helm template sanity (local, sno, prod)
	@for env in local sno prod; do \
	  echo "==> argocd-apps ($$env)"; \
	  helm template charts/argocd-apps --set envFilter=$$env >/dev/null || exit 1; \
	done

validate: hu ## run full validation (lint, render, schema, policy)
	@bash scripts/validate.sh

compute-appversion: ## compute composite appVersion from values-$(ENV).yaml and update umbrella Chart (ENV=local|sno|prod)
	@ENV=${ENV:-local} bash scripts/compute-appversion.sh $$ENV

verify-release: ## ensure Chart appVersion matches per-env tags and naming
	@bash scripts/verify-release.sh

smoke: ## run cluster smoke checks (ENV=<env> [BOOTSTRAP=true] [BASE_DOMAIN=...])
	@ENV=${ENV} BOOTSTRAP=${BOOTSTRAP} BASE_DOMAIN=${BASE_DOMAIN} bash scripts/smoke.sh ${ENV}

smoke-image-update: ## tail updater logs and show app annotations (ENV=<env> NS=openshift-gitops)
	@bash scripts/smoke-image-update.sh

bump-image: ## create a new tag in Quay from SOURCE_TAG to NEW_TAG (uses skopeo|podman|docker)
	@bash scripts/quay-bump-tag.sh

bump-and-tail: ## bump image in Quay then tail updater logs (ENV=<env> NS=openshift-gitops)
	@bash scripts/quay-bump-tag.sh && bash scripts/smoke-image-update.sh

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

local-e2e: ## interactive helper to prep ENV=local CI/CD flow
	@bash scripts/local-e2e-setup.sh

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

pin-images: ## pin toy-service/toy-web tags (ENVS=local,sno,prod SVC_TAG=... WEB_TAG=... [FREEZE=true] [UNFREEZE=true] [NO_VERIFY=1] [DRY_RUN=true])
	@ENVS="$${ENVS:-local,sno,prod}" \
	 SVC_TAG="$${SVC_TAG:-}" WEB_TAG="$${WEB_TAG:-}" \
	 SVC_REPO="$${SVC_REPO:-}" WEB_REPO="$${WEB_REPO:-}" \
	 FREEZE="$${FREEZE:-false}" UNFREEZE="$${UNFREEZE:-false}" \
	 DRY_RUN="$${DRY_RUN:-false}" ; \
	 ARGS=""; \
	 if [ -n "$$ENVS" ]; then ARGS="$$ARGS --envs $$ENVS"; fi; \
	 if [ -n "$$SVC_TAG" ]; then ARGS="$$ARGS --svc-tag $$SVC_TAG"; fi; \
	 if [ -n "$$WEB_TAG" ]; then ARGS="$$ARGS --web-tag $$WEB_TAG"; fi; \
	 if [ -n "$$SVC_REPO" ]; then ARGS="$$ARGS --svc-repo $$SVC_REPO"; fi; \
	 if [ -n "$$WEB_REPO" ]; then ARGS="$$ARGS --web-repo $$WEB_REPO"; fi; \
	 if [ "$$FREEZE" = "true" ]; then ARGS="$$ARGS --freeze"; fi; \
	 if [ "$$UNFREEZE" = "true" ]; then ARGS="$$ARGS --unfreeze"; fi; \
	 if [ -n "$$NO_VERIFY" ]; then ARGS="$$ARGS --no-verify"; fi; \
	 if [ "$$DRY_RUN" = "true" ]; then ARGS="$$ARGS --dry-run"; fi; \
	 bash scripts/pin-images.sh $$ARGS

freeze-updater: ## set pause:true for Image Updater (ENVS=local,sno,prod) [SERVICES=backend|frontend|backend,frontend]
	@ENVS="$${ENVS:-local,sno,prod}" SERVICES="$${SERVICES:-}" bash scripts/pin-images.sh --envs "$$ENVS" $${SERVICES:+--services $$SERVICES} --freeze --no-verify

unfreeze-updater: ## set pause:false for Image Updater (ENVS=local,sno,prod) [SERVICES=backend|frontend|backend,frontend]
	@ENVS="$${ENVS:-local,sno,prod}" SERVICES="$${SERVICES:-}" bash scripts/pin-images.sh --envs "$$ENVS" $${SERVICES:+--services $$SERVICES} --unfreeze --no-verify
