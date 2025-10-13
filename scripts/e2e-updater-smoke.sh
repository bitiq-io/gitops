#!/usr/bin/env bash
set -Eeuo pipefail

# Smoke-test Argo CD Image Updater end-to-end by bumping a tag in Quay and
# watching for a Git write-back and Argo reconciliation. Defaults to toy-service.
#
# Requirements:
# - oc logged in and cluster reachable
# - argocd-image-updater deployed and configured
# - skopeo|podman|docker available locally; Quay creds if repo is private
# - Updater allow-tags must match the NEW_TAG we create (we use v0.0.0-commit.<hex>)
#
# Usage:
#   ENV=local SERVICE=toy-service QUAY_NAMESPACE=<yours> QUAY_USERNAME=... QUAY_PASSWORD=... \
#     bash scripts/e2e-updater-smoke.sh

log(){ printf '[%s] %s\n' "$(date -Ins)" "$*"; }
err(){ printf '[%s] ERROR: %s\n' "$(date -Ins)" "$*" >&2; }

ENVIRONMENT=${ENV:-local}
SERVICE=${SERVICE:-toy-service}   # toy-service|toy-web
NS_GITOPS=${NS_GITOPS:-openshift-gitops}

APP_NAME="${SERVICE}-${ENVIRONMENT}"

require(){ command -v "$1" >/dev/null 2>&1 || { err "Missing required tool: $1"; exit 1; }; }

require oc
require jq

if ! oc whoami >/dev/null 2>&1; then
  err "oc not logged in"
  exit 1
fi

if ! oc -n "$NS_GITOPS" get application "$APP_NAME" >/dev/null 2>&1; then
  err "Application $NS_GITOPS/$APP_NAME not found"
  exit 1
fi

log "Checking updater annotations on $APP_NAME"
oc -n "$NS_GITOPS" get application "$APP_NAME" -o json | jq -r '.metadata.annotations' 2>/dev/null || true

# Compute an allow-listed tag: v0.0.0-commit.<7-hex>
RAND7=$(xxd -l4 -p /dev/urandom 2>/dev/null | cut -c1-7)
NEW_TAG="v0.0.0-commit.${RAND7}"

# Determine Quay repo defaults based on service
QUAY_REGISTRY=${QUAY_REGISTRY:-quay.io}
QUAY_NAMESPACE=${QUAY_NAMESPACE:-paulcapestany}
if [[ "$SERVICE" == "toy-web" ]]; then
  QUAY_REPOSITORY_DEFAULT=toy-web
else
  QUAY_REPOSITORY_DEFAULT=toy-service
fi
QUAY_REPOSITORY=${QUAY_REPOSITORY:-$QUAY_REPOSITORY_DEFAULT}

log "Bumping Quay tag: ${QUAY_NAMESPACE}/${QUAY_REPOSITORY}:${NEW_TAG} (from SOURCE_TAG=${SOURCE_TAG:-latest})"
QUAY_NAMESPACE="$QUAY_NAMESPACE" QUAY_REPOSITORY="$QUAY_REPOSITORY" NEW_TAG="$NEW_TAG" \
  bash "$(cd "$(dirname "$0")" && pwd)/quay-bump-tag.sh"

log "Tail updater logs for commit/push (2m)"
deadline=$((SECONDS+120))
found=0
while (( SECONDS < deadline )); do
  if oc -n "$NS_GITOPS" logs deploy/argocd-image-updater --since=2m 2>/dev/null \
      | grep -E "(Committing changes to application|Pushed change|Setting new image.*${SERVICE})" >/dev/null; then
    found=1
    break
  fi
  sleep 5
done

if [[ "$found" -ne 1 ]]; then
  err "Updater did not log a commit/push for ${APP_NAME} within 2m"
  exit 1
fi

log "Success: updater activity detected for ${APP_NAME}"
