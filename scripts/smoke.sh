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

# Ensure destination namespace exists and is labeled for OpenShift GitOps RBAC
ns="bitiq-${ENVIRONMENT}"
if ! oc get ns "${ns}" >/dev/null 2>&1; then
  log "Creating destination namespace ${ns}"
  oc create ns "${ns}" >/dev/null 2>&1 || true
fi
managed_label=$(oc get ns "${ns}" -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/managed-by}' 2>/dev/null || echo "")
if [[ "${managed_label}" != "openshift-gitops" ]]; then
  log "Labeling ${ns} with argocd.argoproj.io/managed-by=openshift-gitops"
  oc label ns "${ns}" argocd.argoproj.io/managed-by=openshift-gitops --overwrite >/dev/null 2>&1 || true
fi

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

for child in toy-service toy-web; do
  child_app="${child}-${ENVIRONMENT}"
  if oc -n openshift-gitops get application "${child_app}" >/dev/null 2>&1; then
    health=$(oc -n openshift-gitops get application "${child_app}" -o jsonpath='{.status.health.status}' || echo "Unknown")
    sync=$(oc -n openshift-gitops get application "${child_app}" -o jsonpath='{.status.sync.status}' || echo "Unknown")
    log "Application ${child_app}: health=${health} sync=${sync}"
  else
    log "Application ${child_app} not found (yet)."
  fi
done

ns="bitiq-${ENVIRONMENT}"
log "Checking sample app Routes in namespace ${ns}"
for route in toy-service toy-web; do
  host=$(oc -n "${ns}" get route "${route}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  if [[ -n "${host}" ]]; then
    log "Route ${route}: https://${host}"
  else
    log "Route ${route} not found (yet)."
  fi
done

log "Smoke test completed."
