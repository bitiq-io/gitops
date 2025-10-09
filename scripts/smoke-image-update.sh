#!/usr/bin/env bash
set -euo pipefail

# Tiny smoke helper for Argo CD Image Updater
# - Shows annotations on the Application (write-back, branch, dry-run)
# - Prints sourceType so you can see when Argo marks it as Helm
# - Tails the updater logs for live feedback (Ctrl-C to stop)
#
# Usage:
#   ENV=local NS=openshift-gitops make smoke-image-update
# or directly:
#   ENV=local NS=openshift-gitops bash scripts/smoke-image-update.sh

ENV="${ENV:-local}"
NS="${NS:-openshift-gitops}"
APP="${APP:-toy-service-${ENV}}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }

require oc

if ! oc whoami >/dev/null 2>&1; then
  echo "Not logged into a cluster (oc whoami failed)" >&2
  exit 1
fi

if ! oc -n "$NS" get application "$APP" >/dev/null 2>&1; then
  echo "Application '$APP' not found in namespace '$NS'" >&2
  exit 1
fi

echo "==> Application: $NS/$APP"
echo "==> Annotations (sanity check)"
# Show the annotations block for easy visual verification
oc -n "$NS" get application "$APP" -o yaml | sed -n '/^  annotations:/,/^  [^ ]/p' || true

echo
echo -n "==> ArgoCD sourceType: "
oc -n "$NS" get application "$APP" -o jsonpath='{.status.sourceType}' 2>/dev/null || true
echo

echo
echo "==> Recent updater logs (last 10m)"
oc -n "$NS" logs deploy/argocd-image-updater --since=10m 2>/dev/null | tail -n 200 || true

echo
echo "==> Key decision lines (last 10m)"
oc -n "$NS" logs deploy/argocd-image-updater --since=10m 2>/dev/null \
  | grep -E "(eligible for consideration|Setting new image|Dry run|Committing|Pushed change|skipping app)" || true

cat <<'EOF'

Key lines to look for:
  - Dry run - not committing ...          => disable dry-run on the Application
  - Committing changes to application ...  => updater is writing to Git
  - Pushed change                         => Git push succeeded

Starting live log tail (Ctrl-C to stop)...
EOF

oc -n "$NS" logs deploy/argocd-image-updater -f --since=1m
