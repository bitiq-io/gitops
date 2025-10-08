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
  ENV                : local | sno | prod   (default: local)
  BASE_DOMAIN        : base DNS for app routes (default: apps-crc.testing for local; REQUIRED for sno/prod)
  GIT_REPO_URL       : this repo URL (default: autodetect via 'git remote get-url origin', else prompts)
  TARGET_REV         : Git revision Argo should track (default: main)
  PLATFORMS_OVERRIDE : optional imageUpdater platform override for the selected ENV (e.g., linux/arm64)
  TEKTON_FSGROUP     : optional override for Tekton TaskRun fsGroup (auto-detected on OpenShift if unset)

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

# Optional platforms override (helps when node architecture differs from defaults)
PLATFORMS_OVERRIDE="${PLATFORMS_OVERRIDE:-}"
PLATFORM_ARGS=()
# Determine env index for overrides propagated via ApplicationSet
case "$ENV" in
  local) env_index=0 ;;
  sno)   env_index=1 ;;
  prod)  env_index=2 ;;
  *)     env_index=0 ;;
esac
if [[ -n "$PLATFORMS_OVERRIDE" ]]; then
  log "Overriding envs[${env_index}].platforms to ${PLATFORMS_OVERRIDE}"
  PLATFORM_ARGS=(--set-string "envs[${env_index}].platforms=${PLATFORMS_OVERRIDE}")
fi

# Optional: auto-detect a suitable fsGroup for Tekton workspaces (PVCs)
# On OpenShift, pods run with a random UID from a namespace range; ensuring the
# workspace PVC is group-writable avoids git-clone permission errors.
detect_fsgroup() {
  # Allow explicit override
  if [[ -n "${TEKTON_FSGROUP:-}" ]]; then
    echo "$TEKTON_FSGROUP"
    return 0
  fi
  # Try OpenShift Project annotation first, then Namespace
  local ann; ann=$(oc get project openshift-pipelines -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.supplemental-groups}' 2>/dev/null || true)
  if [[ -z "$ann" ]]; then
    ann=$(oc get ns openshift-pipelines -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.supplemental-groups}' 2>/dev/null || true)
  fi
  if [[ -n "$ann" ]]; then
    # Supported formats: "<start>/<size>" or "<start>-<end>"
    if [[ "$ann" =~ ^([0-9]+)[/\-] ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
  fi
  # Fallback: empty (let SCC/defaults apply)
  echo ""
}

TEKTON_FS_GROUP="$(detect_fsgroup)"
if [[ -n "$TEKTON_FS_GROUP" ]]; then
  log "Detected Tekton fsGroup for openshift-pipelines: ${TEKTON_FS_GROUP}"
else
  log "Tekton fsGroup not detected; proceeding with cluster defaults"
fi

# Sanity checks: cluster login
oc whoami >/dev/null || { log "FATAL: oc not logged in"; exit 1; }
oc api-resources >/dev/null || { log "FATAL: cannot reach cluster"; exit 1; }

# 1) Install operators (Subscriptions) into openshift-operators
log "Installing/ensuring OpenShift GitOps & Pipelines operators via OLM Subscriptions…"
helm upgrade --install bootstrap-operators charts/bootstrap-operators \
  --namespace openshift-operators --create-namespace \
  --wait --timeout 10m

# Optionally tune Tekton Results for local envs before creating any PipelineRuns
configure_tekton_results() {
  local want_results=${TEKTON_RESULTS:-}
  if [[ "$ENV" != "local" ]]; then
    return 0
  fi
  if [[ "$want_results" == "true" ]]; then
    log "ENV=local but TEKTON_RESULTS=true; leaving Tekton Results enabled"
    if [[ -n "${TEKTON_RESULTS_STORAGE:-}" ]]; then
      log "Attempting to set Tekton Results storage to ${TEKTON_RESULTS_STORAGE} (if supported)"
    fi
  else
    log "ENV=local: disabling Tekton Results addon by default (set TEKTON_RESULTS=true to keep it)"
  fi

  # Wait for TektonConfig CRD to exist (operator install may lag)
  for i in {1..60}; do
    if oc get crd tektonconfigs.operator.tekton.dev >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done
  if ! oc get crd tektonconfigs.operator.tekton.dev >/dev/null 2>&1; then
    log "TektonConfig CRD not found; skipping Tekton Results configuration"
    return 0
  fi

  # Detect scope and location of the TektonConfig named 'config'
  local name="config"
  local ns=""
  if oc get tektonconfig "$name" >/dev/null 2>&1; then
    ns=""  # cluster-scoped
  else
    ns=$(oc get tektonconfigs.operator.tekton.dev -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' | awk '$2=="config" {print $1; exit}')
  fi

  local patch_scope=(tektonconfig "$name")
  if [[ -n "$ns" ]]; then
    patch_scope=(-n "$ns" tektonconfig "$name")
  fi

  # Apply desired settings
  if [[ "$want_results" == "true" ]]; then
    # Ensure Results is enabled at the TektonConfig layer for clusters that gate it there
    oc "${patch_scope[@]}" patch --type merge -p '{"spec":{"result":{"disabled":false}}}' >/dev/null 2>&1 || true
    # Optional: attempt storage tuning via TektonConfig params if supported
    if [[ -n "${TEKTON_RESULTS_STORAGE:-}" ]]; then
      oc "${patch_scope[@]}" patch --type merge -p '{"spec":{"addon":{"params":[{"name":"tekton-results-postgres-storage","value":"'"${TEKTON_RESULTS_STORAGE}"'"}]}}}' >/dev/null 2>&1 || true
    fi
  else
    # Primary: disable via TektonConfig.spec.result.disabled when available (OCP Pipelines 1.20+)
    oc "${patch_scope[@]}" patch --type merge -p '{"spec":{"result":{"disabled":true}}}' >/dev/null 2>&1 || true
    # Fallbacks for older operators (ignore errors if unsupported)
    oc "${patch_scope[@]}" patch --type merge -p '{"spec":{"addon":{"params":[{"name":"enable-tekton-results","value":"false"}]}}}' >/dev/null 2>&1 || true
    oc "${patch_scope[@]}" patch --type merge -p '{"spec":{"addon":{"enableResults":false}}}' >/dev/null 2>&1 || true
    # Best-effort cleanup to reclaim space on CRC
    oc -n openshift-pipelines delete statefulset -l app.kubernetes.io/name=tekton-results-postgres >/dev/null 2>&1 || true
    oc -n openshift-pipelines delete pvc -l app.kubernetes.io/name=tekton-results-postgres >/dev/null 2>&1 || true
    # Also stop API/watch deployments if present
    oc -n openshift-pipelines scale deploy -l app.kubernetes.io/name=tekton-results-api --replicas=0 >/dev/null 2>&1 || true
    oc -n openshift-pipelines scale deploy -l app.kubernetes.io/name=tekton-results-watcher --replicas=0 >/dev/null 2>&1 || true
    # And remove the TektonResult CR if created by the operator
    oc delete tektonresults.operator.tekton.dev result >/dev/null 2>&1 || true
    oc delete tektonresults result >/dev/null 2>&1 || true
  fi
}

configure_tekton_results

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
helm_args=(
  --namespace openshift-gitops
  --set-string repoUrl="${GIT_REPO_URL}"
  --set-string targetRevision="${TARGET_REV}"
  --set-string baseDomainOverride="${BASE_DOMAIN}"
  --set-string envFilter="${ENV}"
)
if [[ ${#PLATFORM_ARGS[@]} -gt 0 ]]; then
  helm_args+=("${PLATFORM_ARGS[@]}")
fi
if [[ -n "$TEKTON_FS_GROUP" ]]; then
  # Pass through to envs[<idx>].tektonFsGroup; ApplicationSet will map this to umbrella ciPipelines.fsGroup
  helm_args+=(--set-string "envs[${env_index}].tektonFsGroup=${TEKTON_FS_GROUP}")
fi
helm_args+=(--wait --timeout 5m)

helm upgrade --install argocd-apps charts/argocd-apps \
  --reset-values -f charts/argocd-apps/values.yaml "${helm_args[@]}"

# Ensure destination namespace exists and is managed by this Argo CD instance
app_ns="bitiq-${ENV}"
if ! oc get ns "${app_ns}" >/dev/null 2>&1; then
  log "Creating destination namespace ${app_ns}"
  oc create ns "${app_ns}"
fi
log "Labeling ${app_ns} with argocd.argoproj.io/managed-by=openshift-gitops"
oc label ns "${app_ns}" argocd.argoproj.io/managed-by=openshift-gitops --overwrite >/dev/null 2>&1 || true

# 4) Wait for umbrella Application to appear and become Healthy/Synced
umbrella_app="bitiq-umbrella-${ENV}"
log "Waiting for Application ${umbrella_app} to appear in openshift-gitops…"
for i in {1..60}; do
  if oc -n openshift-gitops get application "${umbrella_app}" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if ! oc -n openshift-gitops get application "${umbrella_app}" >/dev/null 2>&1; then
  log "WARNING: ${umbrella_app} not found yet; controller may still be reconciling."
else
  log "Waiting for ${umbrella_app} to reach Synced/Healthy…"
  timeout=600
  interval=10
  elapsed=0
  while (( elapsed < timeout )); do
    health=$(oc -n openshift-gitops get application "${umbrella_app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    sync=$(oc -n openshift-gitops get application "${umbrella_app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    if [[ "$health" == "Healthy" && "$sync" == "Synced" ]]; then
      log "${umbrella_app}: health=${health} sync=${sync}"
      break
    fi
    sleep ${interval}; elapsed=$((elapsed+interval))
  done
  if (( elapsed >= timeout )); then
    log "WARNING: ${umbrella_app} did not become Healthy/Synced within $timeout seconds (health=${health} sync=${sync})."
  fi
fi

# 5) Wait for child Applications to reconcile (best-effort)
wait_app() {
  local name=$1; local ns=openshift-gitops; local timeout=${2:-600}; local interval=10; local elapsed=0
  log "Waiting for Application ${name} to reach Synced/Healthy…"
  for i in {1..60}; do
    if oc -n "$ns" get application "$name" >/dev/null 2>&1; then break; fi
    sleep 5
  done
  if ! oc -n "$ns" get application "$name" >/dev/null 2>&1; then
    log "WARNING: ${name} not found; skipping wait."
    return 0
  fi
  while (( elapsed < timeout )); do
    local health=$(oc -n "$ns" get application "$name" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    local sync=$(oc -n "$ns" get application "$name" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    if [[ "$health" == "Healthy" && "$sync" == "Synced" ]]; then
      log "${name}: health=${health} sync=${sync}"
      return 0
    fi
    sleep ${interval}; elapsed=$((elapsed+interval))
  done
  log "WARNING: ${name} did not become Healthy/Synced within ${timeout}s."
}

wait_app "image-updater-${ENV}" 300 || true
wait_app "ci-pipelines-${ENV}" 300 || true
wait_app "bitiq-sample-app-${ENV}" 600 || true

log "Bootstrap complete. Open the ArgoCD UI route in 'openshift-gitops' and watch:"
log "  ApplicationSet: bitiq-umbrella-by-env  →  Application: bitiq-umbrella-${ENV}"
