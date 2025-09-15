#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENVIRONMENT="${ENV:-${1:-local}}"
BASE_DOMAIN_DEFAULT="apps-crc.testing"
BASE_DOMAIN="${BASE_DOMAIN:-$BASE_DOMAIN_DEFAULT}"

log(){ printf '[%s] %s\n' "$(date -Ins)" "$*"; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1"; exit 1; }; }

need oc

log "Smoke test starting for ENV=${ENVIRONMENT} BASE_DOMAIN=${BASE_DOMAIN}"

if ! oc whoami >/dev/null 2>&1; then
  echo "Not logged into a cluster. Please 'oc login ...' first." >&2
  exit 1
fi

log "Cluster: $(oc whoami --show-server) as $(oc whoami)"

maybe_bootstrap=${BOOTSTRAP:-}
if [[ "${maybe_bootstrap}" == "true" ]]; then
  log "Running bootstrap.sh (ENV=${ENVIRONMENT})"
  ENV=${ENVIRONMENT} BASE_DOMAIN=${BASE_DOMAIN} bash "${ROOT_DIR}/scripts/bootstrap.sh"
fi

log "Waiting for operators CSVs to be Succeeded (openshift-operators)"
timeout=600
interval=10
elapsed=0
while (( elapsed < timeout )); do
  ok_count=$(oc -n openshift-operators get csv -o json 2>/dev/null \
    | jq '[.items[] | select(.metadata.name|test("gitops|pipelines")) | select(.status.phase=="Succeeded")] | length') || ok_count=0
  if [[ "${ok_count}" =~ ^[0-9]+$ ]] && (( ok_count >= 2 )); then
    break
  fi
  sleep ${interval}; elapsed=$((elapsed+interval))
done

log "Checking Argo CD namespace"
oc -n openshift-gitops get pods || true

app_name="bitiq-umbrella-${ENVIRONMENT}"
log "Waiting for Application ${app_name} to appear"
elapsed=0
while (( elapsed < timeout )); do
  if oc -n openshift-gitops get application "${app_name}" >/dev/null 2>&1; then
    break
  fi
  sleep ${interval}; elapsed=$((elapsed+interval))
done

if oc -n openshift-gitops get application "${app_name}" >/dev/null 2>&1; then
  health=$(oc -n openshift-gitops get application "${app_name}" -o jsonpath='{.status.health.status}' || echo "Unknown")
  sync=$(oc -n openshift-gitops get application "${app_name}" -o jsonpath='{.status.sync.status}' || echo "Unknown")
  log "Application ${app_name}: health=${health} sync=${sync}"
else
  log "Application ${app_name} not found (yet)."
fi

ns="bitiq-${ENVIRONMENT}"
log "Checking sample app Route in namespace ${ns}"
host=$(oc -n "${ns}" get route bitiq-sample-app -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -n "${host}" ]]; then
  log "Sample app route: https://${host}"
else
  log "Sample app route not found (yet)."
fi

log "Smoke test completed."

