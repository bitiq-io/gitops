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
DRY_RUN=false
APPS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NS="$2"; shift 2 ;;
    -e|--env)
      ENV_ARG="$2"; shift 2 ;;
    -s|--source)
      SOURCE="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=true; shift ;;
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

  # Build RS table: name|image|created|hash|ready
  local rs_table
  rs_table="$(oc -n "$ns" get rs -l app.kubernetes.io/name="${app}" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.template.spec.containers[0].image}{"|"}{.metadata.creationTimestamp}{"|"}{.metadata.labels.pod-template-hash}{"|"}{.status.readyReplicas}{"\n"}{end}')"
  if [[ -z "$rs_table" ]]; then
    log "No ReplicaSets found for ${app}; skipping"
    return 0
  fi

  # Choose desired RS safely:
  # 1) If desired_img known: pick RS with image==desired_img and with max readyReplicas; if none, pick newest with that image.
  # 2) Else pick RS with max readyReplicas; if none ready, pick newest overall.
  local active_rs active_hash
  if [[ -n "$desired_img" ]]; then
    active_rs="$(awk -F '|' -v img="$desired_img" 'BEGIN{best="";bestReady=-1} $2==img {r=$5+0; if (r>bestReady){best=$0;bestReady=r}} END{print best}' <<< "$rs_table" | awk -F '|' '{print $1}')"
    if [[ -z "$active_rs" ]]; then
      active_rs="$(awk -F '|' -v img="$desired_img" '$2==img {last=$1} END{print last}' <<< "$rs_table")"
    fi
  fi
  if [[ -z "$active_rs" ]]; then
    active_rs="$(awk -F '|' 'BEGIN{best="";bestReady=-1} {r=$5+0; if (r>bestReady){best=$1;bestReady=r}} END{print best}' <<< "$rs_table")"
  fi
  if [[ -z "$active_rs" ]]; then
    active_rs="$(awk -F '|' '{last=$1} END{print last}' <<< "$rs_table")"
  fi
  active_hash="$(awk -F '|' -v n="$active_rs" '$1==n {print $4}' <<< "$rs_table")"
  log "Active RS: ${active_rs} (hash=${active_hash})"

  # Ensure desired RS has desired replicas
  if [[ "$DRY_RUN" == true ]]; then
    log "DRY-RUN: would patch rs/${active_rs} replicas=${desired_replicas}"
  else
    oc -n "$ns" patch rs "$active_rs" --type=merge -p '{"spec":{"replicas":'"${desired_replicas}"'}}' >/dev/null || true
  fi

  # Scale other RS to 0, but never scale down RS that currently has Ready>0 unless it is NOT the chosen active RS AND desired_img is known and different.
  log "Scaling non-desired ReplicaSets to 0 (safe guard on Ready>0)..."
  while IFS='|' read -r name image created hash ready; do
    [[ -z "$name" ]] && continue
    if [[ "$name" == "$active_rs" ]]; then continue; fi
    if [[ ${ready:-0} -gt 0 && ( -z "$desired_img" || "$image" == "$desired_img" ) ]]; then
      log "  skip $name (ready=$ready, image looks desired)"
      continue
    fi
    if [[ "$DRY_RUN" == true ]]; then
      log "  DRY-RUN: would scale $name -> 0"
    else
      oc -n "$ns" patch rs "$name" --type=merge -p '{"spec":{"replicas":0}}' >/dev/null || true
      log "  scaled $name -> 0"
    fi
  done <<< "$rs_table"

  # Delete pods not matching the active hash
  log "Deleting stray pods not on desired hash..."
  while read -r name hash; do
    [[ -z "$name" ]] && continue
    if [[ "$hash" != "$active_hash" ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        log "  DRY-RUN: would delete pod $name (hash=$hash)"
      else
        oc -n "$ns" delete pod "$name" --grace-period=0 --force >/dev/null || true
        log "  deleted pod $name (hash=$hash)"
      fi
    fi
  done < <(oc -n "$ns" get pods -l app.kubernetes.io/name="${app}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.pod-template-hash}{"\n"}{end}')

  # Wait for rollout
  if [[ "$DRY_RUN" == true ]]; then
    log "DRY-RUN: would wait for rollout of ${app}"
  else
    log "Waiting for ${app} rollout..."
    oc -n "$ns" rollout status deploy/"$app" --timeout=300s || {
      err "Rollout did not complete for ${app}"; return 1; }
  fi
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
