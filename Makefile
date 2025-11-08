SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

CHARTS := charts/bootstrap-operators charts/argocd-apps charts/bitiq-umbrella charts/image-updater charts/ci-pipelines charts/toy-service charts/toy-web charts/strfry charts/ollama charts/nostr-query charts/nostr-threads charts/nostr-thread-copier charts/nostouch charts/vault-runtime charts/vault-config charts/vault-dev charts/nostr-site charts/couchbase-cluster

# Export common secret/env overrides so recipe shells inherit them.
# This makes `make dev-vault GITHUB_WEBHOOK_SECRET=...` reliably pass through
# to scripts, avoiding placeholder fallbacks.
export GITHUB_WEBHOOK_SECRET
export ARGOCD_TOKEN
export QUAY_USERNAME
export QUAY_PASSWORD
export QUAY_EMAIL
export QUAY_DOCKERCONFIGJSON
export VAULT_OPERATORS
export DEV_VAULT_IMAGE
export DEV_VAULT_IMPORT
export DEV_VAULT_IMPORT_TIMEOUT

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

lint: ## helm lint all charts
	@for c in $(CHARTS); do \
	  echo "==> helm lint $$c"; \
	if [ "$$c" = "charts/toy-service" ] || [ "$$c" = "charts/toy-web" ] || [ "$$c" = "charts/nostr-site" ] || [ "$$c" = "charts/couchbase-cluster" ] || [ "$$c" = "charts/strfry" ] || [ "$$c" = "charts/ollama" ] || [ "$$c" = "charts/nostr-query" ] || [ "$$c" = "charts/nostr-threads" ] || [ "$$c" = "charts/nostr-thread-copier" ] || [ "$$c" = "charts/nostouch" ]; then \
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

ddns-sanity: ## run DDNS updater sanity (offline, no AWS/network reads)
	@echo "==> ddns sanity (dry-run, skip lookup)";
	@ROUTE53_DDNS_DEBUG=1 \
	 ROUTE53_DDNS_WAN_IP=203.0.113.10 \
	 ROUTE53_DDNS_ZONES_FILE=docs/examples/route53-apex-ddns.zones \
	 ROUTE53_DDNS_SKIP_LOOKUP=1 \
	 bash -lc 'bash scripts/route53-apex-ddns.sh --dry-run'

compute-appversion: ## compute composite appVersion from values-$(ENV).yaml and update umbrella Chart (ENV=local|sno|prod)
	@ENV=${ENV:-local} bash scripts/compute-appversion.sh $$ENV

verify-release: ## ensure Chart appVersion matches per-env tags and naming
	@bash scripts/verify-release.sh

smoke: ## run cluster smoke checks (ENV=<env> [BOOTSTRAP=true] [BASE_DOMAIN=...])
	@ENV=${ENV} BOOTSTRAP=${BOOTSTRAP} BASE_DOMAIN=${BASE_DOMAIN} bash scripts/smoke.sh ${ENV}

smoke-image-update: ## tail updater logs and show app annotations (ENV=<env> NS=openshift-gitops)
	@bash scripts/smoke-image-update.sh

dev-vault: ## Deploy a dev Vault, seed secrets, and reconcile via Vault operators (ENV=local helper)
	@bash scripts/dev-vault.sh up

dev-vault-down: ## Tear down the dev Vault helper deployment
	@bash scripts/dev-vault.sh down

audit-secrets: ## Audit VSO-managed Secrets for placeholder/demo values
	@bash -eu -o pipefail -c '
	  echo "[audit] Scanning VaultStaticSecrets and their destination Secrets…";
	  oc get vaultstaticsecrets.secrets.hashicorp.com -A -o json | jq -r \
	    '.items[] | [.metadata.namespace, .spec.destination.name, .spec.destination.type] | @tsv' \
	  | while IFS=$'\t' read -r ns name type; do \
	      echo "- $$ns/$$name ($$type)"; \
	      if [ "$$type" = "kubernetes.io/dockerconfigjson" ]; then \
	        auth=$$(oc -n "$$ns" get secret "$$name" -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | base64 -d | jq -r '.auths["quay.io"].auth // empty'); \
	        if [ "$$auth" = "ZGVtbzpkZW1v" ]; then echo "  quay auth=<placeholder: demo:demo>"; else echo "  quay auth=<present,len=$${#auth}>"; fi; \
	      else \
	        for k in $$(oc -n "$$ns" get secret "$$name" -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]?'); do \
	          v=$$(oc -n "$$ns" get secret "$$name" -o jsonpath="{.data.$$k}" 2>/dev/null | base64 -d || true); \
	          case "$$v" in \
	            local-*|*LOCAL_FAKE_SECRET*|*CHANGEME*) echo "  $$k=<placeholder: $$v>";; \
	            *) echo "  $$k=<present,len=$${#v}>";; \
	          esac; \
	        done; \
	      fi; \
	    done || true;
	'

bump-image: ## create a new tag in Quay from SOURCE_TAG to NEW_TAG (uses skopeo|podman|docker)
	@bash scripts/quay-bump-tag.sh

bump-and-tail: ## bump image in Quay then tail updater logs (ENV=<env> NS=openshift-gitops)
	@bash scripts/quay-bump-tag.sh && bash scripts/smoke-image-update.sh

tekton-setup: ## create image ns + grant pusher (webhook secret is Vault-managed via operators; seed Vault instead)
	@oc new-project bitiq-ci >/dev/null 2>&1 || true
	@oc policy add-role-to-user system:image-pusher system:serviceaccount:openshift-pipelines:pipeline -n bitiq-ci >/dev/null 2>&1 || true
	@echo "[INFO] Webhook secret is managed via Vault operators (VSO). Seed Vault at gitops/data/github/webhook (key: token) and run 'make dev-vault'."

local-e2e: ## interactive helper to prep ENV=local CI/CD flow
	@bash scripts/local-e2e-setup.sh

quay-secret: ## DEPRECATED: use Vault (VSO) (seed gitops/data/registry/quay) then make dev-vault
	@echo "[DEPRECATED] Quay credentials are managed via Vault (VSO). Seed Vault at gitops/data/registry/quay (key: dockerconfigjson) and run 'make dev-vault'." && exit 1

image-updater-secret: ## DEPRECATED: use Vault (VSO) (seed gitops/data/argocd/image-updater) then make dev-vault
	@echo "[DEPRECATED] Argo CD Image Updater token is managed via Vault (VSO). Seed Vault at gitops/data/argocd/image-updater (key: token) and run 'make dev-vault'." && exit 1
dev-setup: ## install local commit-msg hook (requires Node/npm)
	@bash scripts/dev-setup.sh

e2e-updater-smoke: ## bump Quay tag and assert updater write-back (ENV=local [SERVICE=toy-service|toy-web])
	@bash scripts/e2e-updater-smoke.sh

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
	@ENVS="$${ENVS:-local,sno,prod}" \
	 SERVICES="$${SERVICES:-}" ; \
	 ARGS=""; \
	 if [ -n "$$ENVS" ]; then ARGS="$$ARGS --envs $$ENVS"; fi; \
	 if [ -n "$$SERVICES" ]; then ARGS="$$ARGS --services $$SERVICES"; fi; \
	 bash scripts/pin-images.sh $$ARGS --freeze --no-verify

unfreeze-updater: ## set pause:false for Image Updater (ENVS=local,sno,prod) [SERVICES=backend|frontend|backend,frontend]
	@ENVS="$${ENVS:-local,sno,prod}" \
	 SERVICES="$${SERVICES:-}" ; \
	 ARGS=""; \
	 if [ -n "$$ENVS" ]; then ARGS="$$ARGS --envs $$ENVS"; fi; \
	 if [ -n "$$SERVICES" ]; then ARGS="$$ARGS --services $$SERVICES"; fi; \
	 bash scripts/pin-images.sh $$ARGS --unfreeze --no-verify
