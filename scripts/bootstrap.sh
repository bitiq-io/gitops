#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[%s] %s\n' "$(date -Ins)" "$*"; }

require() {
  command -v "$1" >/dev/null 2>&1 || { log "FATAL: '$1' not found in PATH"; exit 1; }
}

usage() {
  cat <<EOF
gitops bootstrap

Environment variables:
  ENV            : local | sno | prod   (default: local)
  BASE_DOMAIN    : base DNS for app routes (default: apps-crc.testing for local; REQUIRED for sno/prod)
  GIT_REPO_URL   : this repo URL (default: autodetect via 'git remote get-url origin', else prompts)
  TARGET_REV     : Git revision Argo should track (default: main)

Examples:
  ENV=local ./scripts/bootstrap.sh
  ENV=sno BASE_DOMAIN=apps.sno.example ./scripts/bootstrap.sh
EOF
}

[[ "${1:-}" =~ ^-h|--help$ ]] && { usage; exit 0; }

require oc
require helm

ENV="${ENV:-local}"
TARGET_REV="${TARGET_REV:-main}"

# Detect repo URL if not provided
if [[ -z "${GIT_REPO_URL:-}" ]]; then
  if GIT_REPO_URL="$(git remote get-url origin 2>/dev/null)"; then
    log "Detected GIT_REPO_URL=${GIT_REPO_URL}"
  else
    log "FATAL: GIT_REPO_URL not set and repo URL not detected."
    exit 1
  fi
fi

# Base domain defaults
case "$ENV" in
  local)  BASE_DOMAIN="${BASE_DOMAIN:-apps-crc.testing}";;
  sno|prod) : "${BASE_DOMAIN:?Set BASE_DOMAIN for ${ENV}, e.g., apps.sno.example}";;
  *) log "FATAL: ENV must be one of local|sno|prod"; exit 1;;
esac

log "ENV=${ENV}  BASE_DOMAIN=${BASE_DOMAIN}  GIT_REPO_URL=${GIT_REPO_URL}  TARGET_REV=${TARGET_REV}"

# Sanity checks: cluster login
oc whoami >/dev/null || { log "FATAL: oc not logged in"; exit 1; }
oc api-resources >/dev/null || { log "FATAL: cannot reach cluster"; exit 1; }

# 1) Install operators (Subscriptions) into openshift-operators
log "Installing/ensuring OpenShift GitOps & Pipelines operators via OLM Subscriptions…"
helm upgrade --install bootstrap-operators charts/bootstrap-operators \
  --namespace openshift-operators --create-namespace \
  --wait --timeout 10m

# 2) Wait for ArgoCD default instance route to be ready (if operator creates one)
log "Waiting for Argo CD server route in 'openshift-gitops'…"
if ! oc get ns openshift-gitops >/dev/null 2>&1; then
  log "Creating namespace openshift-gitops"
  oc create ns openshift-gitops
fi

# Best-effort wait loop for route
for i in {1..60}; do
  if oc get route -n openshift-gitops -o name | grep -q 'openshift-gitops.*server' ; then
    log "Argo CD route found."
    break
  fi
  sleep 5
done

# 3) Install ApplicationSet that renders ONE umbrella app for the selected ENV
log "Installing ApplicationSet (argocd-apps) for ENV=${ENV}…"
helm upgrade --install argocd-apps charts/argocd-apps \
  --namespace openshift-gitops \
  --set-string repoUrl="${GIT_REPO_URL}" \
  --set-string targetRevision="${TARGET_REV}" \
  --set-string baseDomainOverride="${BASE_DOMAIN}" \
  --set-string envFilter="${ENV}" \
  --wait --timeout 5m

log "Bootstrap complete. Open the ArgoCD UI route in 'openshift-gitops' and watch:"
log "  ApplicationSet: bitiq-umbrella-by-env  →  Application: bitiq-umbrella-${ENV}"
