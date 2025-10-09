#!/usr/bin/env bash
# Prune old ReplicaSets and pods for Deployments to clear Degraded state in Argo.
#
# Usage:
#   scripts/prune-old-rs.sh              # defaults: ENV=local -> NS=bitiq-local; apps: toy-service toy-web
#   scripts/prune-old-rs.sh -e sno       # ENV=sno -> NS=bitiq-sno; apps default
#   scripts/prune-old-rs.sh -n my-ns app1 app2
#
# Requirements: oc (logged in).

set -euo pipefail

err() { echo "[ERROR] $*" >&2; }
log() { echo "[INFO]  $*"; }

NS=""
ENV_ARG="${ENV:-local}"
APPS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NS="$2"; shift 2 ;;
    -e|--env)
      ENV_ARG="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,40p' "$0"; exit 0 ;;
    --)
      shift; break ;;
    -*)
      err "Unknown flag: $1"; exit 1 ;;
    *)
      APPS+=("$1"); shift ;;
  esac
done

if ! command -v oc >/dev/null 2>&1; then
  err "oc not found in PATH"; exit 1
fi

# Default namespace from ENV if not provided explicitly
if [[ -z "${NS}" ]]; then
  case "${ENV_ARG}" in
    local|sno|prod) NS="bitiq-${ENV_ARG}" ;;
    *) NS="bitiq-local" ;;
  esac
fi

# Default apps when none provided
if [[ ${#APPS[@]} -eq 0 ]]; then
  APPS=(toy-service toy-web)
fi

log "Namespace: ${NS}"
log "Apps: ${APPS[*]}"

# Ensure namespace exists
if ! oc get ns "${NS}" >/dev/null 2>&1; then
  err "Namespace ${NS} not found"; exit 1
fi

prune_app() {
  local ns="$1" app="$2"
  log "=== App: ${app} ==="
  if ! oc -n "$ns" get deploy "$app" >/dev/null 2>&1; then
    log "Deployment ${app} not found in ${ns}; skipping"
    return 0
  fi

  # Determine active ReplicaSet by Deployment revision; fallback to newest RS
  local rev active_rs active_hash
  rev="$(oc -n "$ns" get deploy "$app" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null || true)"
  if [[ -n "${rev}" ]]; then
    active_rs="$(oc -n "$ns" get rs -l app.kubernetes.io/name="${app}" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\n"}{end}' \
      | awk -F '|' -v r="${rev}" '$2==r {print $1}' | tail -n1)"
  fi
  if [[ -z "${active_rs:-}" ]]; then
    # Fallback to newest by creationTimestamp
    active_rs="$(oc -n "$ns" get rs -l app.kubernetes.io/name="${app}" --sort-by=.metadata.creationTimestamp -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | tail -n1)"
  fi
  if [[ -z "${active_rs}" ]]; then
    log "No ReplicaSets found for ${app}; skipping"
    return 0
  fi

  active_hash="$(oc -n "$ns" get rs "$active_rs" -o jsonpath='{.metadata.labels.pod-template-hash}')"
  log "Active RS: ${active_rs} (hash=${active_hash})"

  # Scale older ReplicaSets to 0 via patch (works even if already 0)
  log "Scaling older ReplicaSets to 0..."
  while IFS= read -r rs; do
    [[ -z "$rs" ]] && continue
    if [[ "$rs" != "$active_rs" ]]; then
      oc -n "$ns" patch rs "$rs" --type=merge -p '{"spec":{"replicas":0}}' >/dev/null || true
      log "  scaled $rs -> 0"
    fi
  done < <(oc -n "$ns" get rs -l app.kubernetes.io/name="${app}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

  # Delete pods not matching the active hash
  log "Deleting stray pods not on active hash..."
  while read -r name hash; do
    [[ -z "$name" ]] && continue
    if [[ "$hash" != "$active_hash" ]]; then
      oc -n "$ns" delete pod "$name" --grace-period=0 --force >/dev/null || true
      log "  deleted pod $name (hash=$hash)"
    fi
  done < <(oc -n "$ns" get pods -l app.kubernetes.io/name="${app}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.pod-template-hash}{"\n"}{end}')

  # Wait for rollout to stabilize
  log "Waiting for ${app} rollout..."
  oc -n "$ns" rollout status deploy/"$app" --timeout=180s || {
    err "Rollout did not complete for ${app}"; return 1; }
}

rc=0
for app in "${APPS[@]}"; do
  if ! prune_app "$NS" "$app"; then rc=1; fi
done

if [[ $rc -eq 0 ]]; then
  log "Prune completed successfully."
else
  err "Prune completed with errors. See logs above."
fi

exit "$rc"

