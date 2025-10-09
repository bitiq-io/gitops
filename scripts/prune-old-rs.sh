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
SOURCE="values"  # values|deployment
APPS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NS="$2"; shift 2 ;;
    -e|--env)
      ENV_ARG="$2"; shift 2 ;;
    -s|--source)
      SOURCE="$2"; shift 2 ;;
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
log "Desired source: ${SOURCE} (values|deployment)"

# Ensure namespace exists
if ! oc get ns "${NS}" >/dev/null 2>&1; then
  err "Namespace ${NS} not found"; exit 1
fi

get_desired_image_from_values() {
  local app="$1" env_name="$2"
  local base_dir script_dir file repo tag
  script_dir="$(cd "$(dirname "$0")" && pwd -P)"
  base_dir="$(cd "${script_dir}/.." && pwd -P)"
  case "$app" in
    toy-service) file="$base_dir/charts/toy-service/values-${env_name}.yaml" ;;
    toy-web)     file="$base_dir/charts/toy-web/values-${env_name}.yaml" ;;
    *) echo ""; return 0 ;;
  esac
  if [[ ! -f "$file" ]]; then
    echo ""; return 0
  fi
  repo="$(awk -F': *' '/^[[:space:]]*repository:/ {print $2; exit}' "$file" | tr -d '"')"
  tag="$(awk -F': *' '/^[[:space:]]*tag:/ {print $2; exit}' "$file" | tr -d '"')"
  if [[ -n "$repo" && -n "$tag" ]]; then
    echo "${repo}:${tag}"
  else
    echo ""
  fi
}

prune_app() {
  local ns="$1" app="$2"
  log "=== App: ${app} ==="
  if ! oc -n "$ns" get deploy "$app" >/dev/null 2>&1; then
    log "Deployment ${app} not found in ${ns}; skipping"
    return 0
  fi

  # Determine desired image from the Deployment template
  local desired_img desired_replicas
  if [[ "$SOURCE" == "values" ]]; then
    desired_img="$(get_desired_image_from_values "$app" "$ENV_ARG" || true)"
  fi
  if [[ -z "$desired_img" ]]; then
    desired_img="$(oc -n "$ns" get deploy "$app" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  fi
  desired_replicas="$(oc -n "$ns" get deploy "$app" -o jsonpath='{.spec.replicas}')"
  [[ -z "$desired_replicas" ]] && desired_replicas=1
  log "Desired image: ${desired_img} (replicas=${desired_replicas})"

  # Find the RS whose pod template image matches the Deployment image; choose newest
  local rs_line active_rs active_hash
  rs_line="$(oc -n "$ns" get rs -l app.kubernetes.io/name="${app}" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.template.spec.containers[0].image}{"|"}{.metadata.creationTimestamp}{"|"}{.metadata.labels.pod-template-hash}{"\n"}{end}' \
    | awk -F '|' -v img="$desired_img" '$2==img {line=$0} END{print line}')"
  if [[ -z "$rs_line" ]]; then
    # Fallback to RS with a Ready pod, otherwise newest
    rs_line="$(oc -n "$ns" get rs -l app.kubernetes.io/name="${app}" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.template.spec.containers[0].image}{"|"}{.metadata.creationTimestamp}{"|"}{.metadata.labels.pod-template-hash}{"|"}{.status.readyReplicas}{"\n"}{end}' \
      | awk -F '|' '$5+0>0 {line=$0} END{print line}')"
  fi
  if [[ -z "$rs_line" ]]; then
    rs_line="$(oc -n "$ns" get rs -l app.kubernetes.io/name="${app}" --sort-by=.metadata.creationTimestamp \
      -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.template.spec.containers[0].image}{"|"}{.metadata.creationTimestamp}{"|"}{.metadata.labels.pod-template-hash}{"\n"}{end}' | tail -n1)"
  fi
  if [[ -z "$rs_line" ]]; then
    log "No ReplicaSets found for ${app}; skipping"
    return 0
  fi

  active_rs="$(awk -F '|' '{print $1}' <<< "$rs_line")"
  active_hash="$(awk -F '|' '{print $4}' <<< "$rs_line")"
  log "Active RS (by image): ${active_rs} (hash=${active_hash})"

  # Ensure desired RS is scaled to desired replicas
  oc -n "$ns" patch rs "$active_rs" --type=merge -p '{"spec":{"replicas":'"${desired_replicas}"'}}' >/dev/null || true

  # Scale all other RS to 0
  log "Scaling older/non-desired ReplicaSets to 0..."
  while IFS= read -r rs; do
    [[ -z "$rs" ]] && continue
    if [[ "$rs" != "$active_rs" ]]; then
      oc -n "$ns" patch rs "$rs" --type=merge -p '{"spec":{"replicas":0}}' >/dev/null || true
      log "  scaled $rs -> 0"
    fi
  done < <(oc -n "$ns" get rs -l app.kubernetes.io/name="${app}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

  # Delete pods not matching the active hash (non-desired RS)
  log "Deleting stray pods not on desired image/hash..."
  while read -r name hash; do
    [[ -z "$name" ]] && continue
    if [[ "$hash" != "$active_hash" ]]; then
      oc -n "$ns" delete pod "$name" --grace-period=0 --force >/dev/null || true
      log "  deleted pod $name (hash=$hash)"
    fi
  done < <(oc -n "$ns" get pods -l app.kubernetes.io/name="${app}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.pod-template-hash}{"\n"}{end}')

  # Wait for rollout to stabilize
  log "Waiting for ${app} rollout..."
  oc -n "$ns" rollout status deploy/"$app" --timeout=240s || {
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
