#!/usr/bin/env bash
set -Eeuo pipefail

# Fast path usage (non-interactive):
#   FAST_PATH=true \
#   ENV=local BASE_DOMAIN=apps-crc.testing \
#   GITHUB_WEBHOOK_SECRET=<secret> \
#   QUAY_USERNAME=<user> QUAY_PASSWORD=<token-or-password> QUAY_EMAIL=<email> \
#   ARGOCD_TOKEN=<argo-cd-api-token> \
#   ARGOCD_REPO_URL=https://github.com/bitiq-io/gitops.git \
#   ARGOCD_REPO_USERNAME=<github-username-or-git> \
#   ARGOCD_REPO_PASSWORD=<github-pat-or-password> \
#   # Optional host-wide creds applied to all repos under URL prefix
#   ARGOCD_REPOCREDS_URL=https://github.com \
#   ARGOCD_REPOCREDS_USERNAME=<github-username-or-git> \
#   ARGOCD_REPOCREDS_PASSWORD=<github-pat-or-password> \
#   ./scripts/local-e2e-setup.sh
#
# Notes:
# - When FAST_PATH=true, any missing env var is treated as "skip that step".
# - Repo credentials are created as an Argo CD repository Secret in openshift-gitops.
#   This avoids requiring argocd CLI login on headless servers.

log() { printf '[%s] %s\n' "$(date -Ins)" "$*"; }
err() { printf '[%s] ERROR: %s\n' "$(date -Ins)" "$*" >&2; }

prompt_yes() {
  local prompt=${1:-Confirm}
  local reply
  read -r -p "$prompt [y/N]: " reply || true
  case "$reply" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) return 1 ;;
  esac
}

read_secret() {
  local prompt=$1
  local var
  read -r -s -p "$prompt" var || true
  printf '\n'
  printf '%s' "$var"
}

require() {
  command -v "$1" >/dev/null 2>&1 || { err "'$1' not found in PATH"; exit 1; }
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
ENVIRONMENT=${ENV:-local}
BASE_DOMAIN=${BASE_DOMAIN:-}
TARGET_REV=${TARGET_REV:-main}

require oc
require helm

if [[ -z "$BASE_DOMAIN" ]]; then
  case "$ENVIRONMENT" in
    local) BASE_DOMAIN=apps-crc.testing ;;
    sno|prod) err "Set BASE_DOMAIN for ENV=$ENVIRONMENT"; exit 1 ;;
    *) err "ENV must be local|sno|prod"; exit 1 ;;
  esac
fi

git_detect_url() {
  git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true
}

GIT_REPO_URL=${GIT_REPO_URL:-$(git_detect_url)}

if [[ -z "$GIT_REPO_URL" ]]; then
  err "Unable to detect GIT_REPO_URL; set env var GIT_REPO_URL"
  exit 1
fi

log "Using ENV=$ENVIRONMENT BASE_DOMAIN=$BASE_DOMAIN TARGET_REV=$TARGET_REV"
log "Repo URL: $GIT_REPO_URL"

if ! oc whoami >/dev/null 2>&1; then
  err "oc is not logged in; run 'oc login' as cluster-admin"
  exit 1
fi

CURRENT_USER=$(oc whoami)
log "Current OpenShift user: $CURRENT_USER"

# Pre-flight permission checks, but avoid hard failure if CRDs are not installed yet
if oc api-resources --api-group=argoproj.io -o name 2>/dev/null | grep -qx 'applications'; then
  if [[ "$(oc auth can-i get applications.argoproj.io -n openshift-gitops)" != "yes" ]]; then
    err "User $CURRENT_USER lacks access to Argo CD Applications in openshift-gitops"
    err "Log in as kubeadmin or grant access: oc adm policy add-role-to-user admin $CURRENT_USER -n openshift-gitops"
    exit 1
  fi
else
  log "Argo CD CRD not found yet; will proceed and re-check after operator install"
fi

if oc api-resources --api-group=tekton.dev -o name 2>/dev/null | grep -qx 'pipelines'; then
  if [[ "$(oc auth can-i get pipelines.tekton.dev -n openshift-pipelines)" != "yes" ]]; then
    err "User $CURRENT_USER lacks access to Tekton pipelines in openshift-pipelines"
    err "Grant access: oc adm policy add-role-to-user admin $CURRENT_USER -n openshift-pipelines"
    exit 1
  fi
else
  log "Tekton CRDs not found yet; will proceed and re-check after operator install"
fi

log "Running bootstrap.sh (skip waits; will configure creds then refresh)"
ENV="$ENVIRONMENT" BASE_DOMAIN="$BASE_DOMAIN" GIT_REPO_URL="$GIT_REPO_URL" TARGET_REV="$TARGET_REV" SKIP_APP_WAIT=true \
  "$REPO_ROOT/scripts/bootstrap.sh"

# Defensive: ensure Tekton Results is disabled and any leftover resources are cleaned up
ensure_disable_tekton_results() {
  log "Ensuring Tekton Results is disabled and cleaned up (ENV=$ENVIRONMENT)"
  # Only relevant for local by default, but safe to run idempotently
  # 1) Wait for TektonConfig CRD; patch disable flags (covering multiple operator versions)
  for i in {1..60}; do
    if oc get crd tektonconfigs.operator.tekton.dev >/dev/null 2>&1; then break; fi
    sleep 2
  done
  if oc get crd tektonconfigs.operator.tekton.dev >/dev/null 2>&1; then
    if oc get tektonconfig config >/dev/null 2>&1; then
      oc patch tektonconfig config --type merge -p '{"spec":{"result":{"disabled":true}}}' >/dev/null 2>&1 || true
      oc patch tektonconfig config --type merge -p '{"spec":{"addon":{"params":[{"name":"enable-tekton-results","value":"false"}]}}}' >/dev/null 2>&1 || true
      oc patch tektonconfig config --type merge -p '{"spec":{"addon":{"enableResults":false}}}' >/dev/null 2>&1 || true
    else
      # Namespaced TektonConfig fallback
      cfg_ns=$(oc get tektonconfigs.operator.tekton.dev -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' 2>/dev/null | awk '$2=="config" {print $1; exit}')
      if [[ -n "$cfg_ns" ]]; then
        oc -n "$cfg_ns" patch tektonconfig config --type merge -p '{"spec":{"result":{"disabled":true}}}' >/dev/null 2>&1 || true
        oc -n "$cfg_ns" patch tektonconfig config --type merge -p '{"spec":{"addon":{"params":[{"name":"enable-tekton-results","value":"false"}]}}}' >/dev/null 2>&1 || true
        oc -n "$cfg_ns" patch tektonconfig config --type merge -p '{"spec":{"addon":{"enableResults":false}}}' >/dev/null 2>&1 || true
      fi
    fi
  fi
  # 2) Delete TektonResults CRs if present (cluster-scoped and legacy)
  oc delete tektonresults.operator.tekton.dev result >/dev/null 2>&1 || true
  oc delete tektonresults result >/dev/null 2>&1 || true
  # 3) Best-effort scale down any API/watch components and drop Postgres resources
  oc -n openshift-pipelines scale deploy -l app.kubernetes.io/name=tekton-results-api --replicas=0 >/dev/null 2>&1 || true
  oc -n openshift-pipelines scale deploy -l app.kubernetes.io/name=tekton-results-watcher --replicas=0 >/dev/null 2>&1 || true
  oc -n openshift-pipelines delete statefulset -l app.kubernetes.io/name=tekton-results-postgres >/dev/null 2>&1 || true
  oc -n openshift-pipelines delete statefulset tekton-results-postgres >/dev/null 2>&1 || true
  oc -n openshift-pipelines delete pvc -l app.kubernetes.io/name=tekton-results-postgres >/dev/null 2>&1 || true
  oc -n openshift-pipelines delete pvc postgredb-tekton-results-postgres-0 >/dev/null 2>&1 || true
}

ensure_disable_tekton_results

# Post-bootstrap permission sanity-checks now that CRDs should exist
if [[ "$(oc auth can-i get applications.argoproj.io -n openshift-gitops)" != "yes" ]]; then
  err "User $CURRENT_USER lacks access to Argo CD Applications in openshift-gitops"
  err "Log in as kubeadmin or grant: oc adm policy add-role-to-user admin $CURRENT_USER -n openshift-gitops"
fi
if [[ "$(oc auth can-i get pipelines.tekton.dev -n openshift-pipelines)" != "yes" ]]; then
  err "User $CURRENT_USER lacks access to Tekton pipelines in openshift-pipelines"
  err "Grant: oc adm policy add-role-to-user admin $CURRENT_USER -n openshift-pipelines"
fi

log "Ensuring application namespace access"
oc new-project bitiq-local >/dev/null 2>&1 || true
oc -n bitiq-local create rolebinding argocd-app-admin \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller >/dev/null 2>&1 || true

# Allow Argo CD application-controller to manage Tekton resources in openshift-pipelines
# This prevents Forbidden errors when syncing the ci-pipelines Application (EventListener, Triggers, Pipelines, Route)
oc -n openshift-pipelines create rolebinding argocd-app-admin \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller >/dev/null 2>&1 || true

# Sanity-check that the Argo CD SA can create Tekton Triggers in openshift-pipelines
if [[ "$(oc auth can-i create eventlisteners.triggers.tekton.dev -n openshift-pipelines \
        --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller)" != "yes" ]]; then
  err "Argo CD SA still lacks permissions in openshift-pipelines; RBAC may be restricted in your env"
  err "Try: oc adm policy add-role-to-user admin system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller -n openshift-pipelines"
fi

log "Ensuring Tekton image namespace and permissions"
oc new-project bitiq-ci >/dev/null 2>&1 || true
oc policy add-role-to-user system:image-pusher system:serviceaccount:openshift-pipelines:pipeline -n bitiq-ci >/dev/null 2>&1 || true

# Fast path: non-interactive secrets and repo creds if env vars are provided
FAST_PATH=${FAST_PATH:-}

# 1) GitHub webhook secret for Tekton Triggers
if [[ "${FAST_PATH}" == "true" ]]; then
  if [[ -n "${GITHUB_WEBHOOK_SECRET:-}" ]]; then
    log "[fast] Applying GitHub webhook secret (openshift-pipelines/github-webhook-secret)"
    oc -n openshift-pipelines create secret generic github-webhook-secret \
      --from-literal=secretToken="${GITHUB_WEBHOOK_SECRET}" \
      --dry-run=client -o yaml | oc apply -f -
  else
    log "[fast] GITHUB_WEBHOOK_SECRET not set; skipping webhook secret"
  fi
fi

# 2) Quay credentials for Tekton SA 'pipeline'
if [[ "${FAST_PATH}" == "true" ]]; then
  if [[ -n "${QUAY_USERNAME:-}" && -n "${QUAY_PASSWORD:-}" && -n "${QUAY_EMAIL:-}" ]]; then
    log "[fast] Applying Quay auth and linking to SA 'pipeline'"
    oc -n openshift-pipelines create secret docker-registry quay-auth \
      --docker-server=quay.io \
      --docker-username="${QUAY_USERNAME}" \
      --docker-password="${QUAY_PASSWORD}" \
      --docker-email="${QUAY_EMAIL}" \
      --dry-run=client -o yaml | oc apply -f -
    oc -n openshift-pipelines annotate secret quay-auth tekton.dev/docker-0=https://quay.io --overwrite >/dev/null 2>&1 || true
    oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount >/dev/null 2>&1 || true
  else
    log "[fast] QUAY_USERNAME/QUAY_PASSWORD/QUAY_EMAIL not fully set; skipping Quay secret"
  fi
fi

# 3) Argo CD Image Updater API token Secret in openshift-gitops
if [[ "${FAST_PATH}" == "true" ]]; then
  if [[ -n "${ARGOCD_TOKEN:-}" ]]; then
    log "[fast] Applying argocd-image-updater-secret in openshift-gitops"
    ARGOCD_TOKEN="${ARGOCD_TOKEN}" make -C "$REPO_ROOT" image-updater-secret >/dev/null
  else
    log "[fast] ARGOCD_TOKEN not set; skipping image-updater secret"
  fi
fi

# 4) Argo CD repo credentials via Secret (avoid argocd CLI)
if [[ "${FAST_PATH}" == "true" ]]; then
  REPO_URL_DEFAULT=${GIT_REPO_URL}
  REPO_URL=${ARGOCD_REPO_URL:-$REPO_URL_DEFAULT}
  # Support GH_PAT as alias for ARGOCD_REPO_PASSWORD
  if [[ -z "${ARGOCD_REPO_PASSWORD:-}" && -n "${GH_PAT:-}" ]]; then
    ARGOCD_REPO_PASSWORD="$GH_PAT"
  fi
  if [[ -n "${REPO_URL}" && -n "${ARGOCD_REPO_PASSWORD:-}" ]]; then
    REPO_USER=${ARGOCD_REPO_USERNAME:-git}
    # Generate a deterministic, DNS-safe name from URL
    SAFE_NAME=$(echo "$REPO_URL" | sed -E 's#https?://##; s#[^a-zA-Z0-9]+#-#g; s#(^-+|-+$)##g')
    SECRET_NAME=${ARGOCD_REPO_SECRET_NAME:-repo-${SAFE_NAME}}
    log "[fast] Applying Argo CD repo credential Secret ${SECRET_NAME} for ${REPO_URL}"
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repository
  annotations:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  url: "${REPO_URL}"
  type: git
  username: "${REPO_USER}"
  password: "${ARGOCD_REPO_PASSWORD}"
EOF
  else
    log "[fast] ARGOCD_REPO_PASSWORD (or GH_PAT) not set; skipping repo credential Secret"
  fi
fi

# 5) Host-wide Argo CD repo-creds (prefix match, e.g., https://github.com)
if [[ "${FAST_PATH}" == "true" ]]; then
  REPOCREDS_URL=${ARGOCD_REPOCREDS_URL:-}
  # Support GH_PAT as alias for ARGOCD_REPOCREDS_PASSWORD
  if [[ -z "${ARGOCD_REPOCREDS_PASSWORD:-}" && -n "${GH_PAT:-}" ]]; then
    ARGOCD_REPOCREDS_PASSWORD="$GH_PAT"
  fi
  if [[ -n "${REPOCREDS_URL}" && -n "${ARGOCD_REPOCREDS_PASSWORD:-}" ]]; then
    REPOCREDS_USER=${ARGOCD_REPOCREDS_USERNAME:-git}
    SAFE_NAME_RC=$(echo "$REPOCREDS_URL" | sed -E 's#https?://##; s#[^a-zA-Z0-9]+#-#g; s#(^-+|-+$)##g')
    SECRET_NAME_RC=${ARGOCD_REPOCREDS_SECRET_NAME:-repocreds-${SAFE_NAME_RC}}
    log "[fast] Applying Argo CD repo-creds Secret ${SECRET_NAME_RC} for prefix ${REPOCREDS_URL}"
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME_RC}
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repo-creds
  annotations:
    argocd.argoproj.io/secret-type: repo-creds
type: Opaque
stringData:
  url: "${REPOCREDS_URL}"
  username: "${REPOCREDS_USER}"
  password: "${ARGOCD_REPOCREDS_PASSWORD}"
EOF
  else
    if [[ -n "${REPOCREDS_URL}" ]]; then
      log "[fast] ARGOCD_REPOCREDS_PASSWORD (or GH_PAT) not set; skipping repo-creds Secret"
    else
      log "[fast] ARGOCD_REPOCREDS_URL not set; skipping repo-creds Secret"
    fi
  fi
fi

if [[ "${FAST_PATH}" == "true" ]]; then
  if oc -n openshift-pipelines get secret github-webhook-secret >/dev/null 2>&1; then
    log "[fast] github-webhook-secret already present"
  else
    log "[fast] github-webhook-secret not found; set GITHUB_WEBHOOK_SECRET and rerun or create manually"
  fi
else
  if oc -n openshift-pipelines get secret github-webhook-secret >/dev/null 2>&1; then
    log "GitHub webhook secret already present (openshift-pipelines/github-webhook-secret)"
    if prompt_yes "Update github-webhook-secret value?"; then
      token=$(read_secret "New GitHub webhook secret token: ")
      if [[ -n "$token" ]]; then
        log "Updating github-webhook-secret"
        oc -n openshift-pipelines create secret generic github-webhook-secret \
          --from-literal=secretToken="$token" --dry-run=client -o yaml | oc apply -f -
      else
        log "No secret provided; keeping existing value"
      fi
    else
      log "Keeping existing github-webhook-secret"
    fi
  else
    if prompt_yes "Create GitHub webhook Secret for Tekton?"; then
      token=$(read_secret "GitHub webhook secret token: ")
      if [[ -n "$token" ]]; then
        log "Creating github-webhook-secret"
        oc -n openshift-pipelines create secret generic github-webhook-secret \
          --from-literal=secretToken="$token" --dry-run=client -o yaml | oc apply -f -
      else
        log "No secret provided; skipping creation"
      fi
    else
      log "Skipping Tekton webhook secret creation"
    fi
  fi
fi

if [[ "${FAST_PATH}" == "true" ]]; then
  if oc -n openshift-pipelines get secret quay-auth >/dev/null 2>&1; then
    log "[fast] quay-auth secret already present"
  else
    log "[fast] quay-auth secret not found; set QUAY_* env vars and rerun or create manually"
  fi
else
  if oc -n openshift-pipelines get secret quay-auth >/dev/null 2>&1; then
    log "Quay credentials already configured (openshift-pipelines/quay-auth)"
    if prompt_yes "Update quay-auth secret?"; then
      read -r -p "Quay username: " quay_user || true
      quay_pass=$(read_secret "Quay password/token: ")
      read -r -p "Quay email: " quay_email || true
      if [[ -n "$quay_user" && -n "$quay_pass" && -n "$quay_email" ]]; then
        log "Updating quay-auth secret"
        oc -n openshift-pipelines create secret docker-registry quay-auth \
          --docker-server=quay.io \
          --docker-username="$quay_user" \
          --docker-password="$quay_pass" \
          --docker-email="$quay_email" \
          --dry-run=client -o yaml | oc apply -f -
        oc -n openshift-pipelines annotate secret quay-auth tekton.dev/docker-0=https://quay.io --overwrite >/dev/null 2>&1 || true
        oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount >/dev/null 2>&1 || true
      else
        log "Missing Quay fields; keeping existing secret"
      fi
    else
      log "Keeping existing quay-auth secret"
    fi
  else
    if prompt_yes "Create Quay credentials for pipeline ServiceAccount?"; then
      read -r -p "Quay username: " quay_user || true
      quay_pass=$(read_secret "Quay password/token: ")
      read -r -p "Quay email: " quay_email || true
      if [[ -n "$quay_user" && -n "$quay_pass" && -n "$quay_email" ]]; then
        log "Creating quay-auth secret"
        oc -n openshift-pipelines create secret docker-registry quay-auth \
          --docker-server=quay.io \
          --docker-username="$quay_user" \
          --docker-password="$quay_pass" \
          --docker-email="$quay_email" \
          --dry-run=client -o yaml | oc apply -f -
        oc -n openshift-pipelines annotate secret quay-auth tekton.dev/docker-0=https://quay.io --overwrite >/dev/null 2>&1 || true
        oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount >/dev/null 2>&1 || true
      else
        log "Missing Quay fields; skipping creation"
      fi
    else
      log "Skipping Quay credential configuration"
    fi
  fi
fi

if [[ "${FAST_PATH}" == "true" ]]; then
  if oc -n openshift-gitops get secret argocd-image-updater-secret >/dev/null 2>&1; then
    log "[fast] argocd-image-updater-secret already present"
  else
    log "[fast] argocd-image-updater-secret not found; set ARGOCD_TOKEN and rerun or create via 'make image-updater-secret'"
  fi
else
  if oc -n openshift-gitops get secret argocd-image-updater-secret >/dev/null 2>&1; then
    log "argocd-image-updater-secret already exists"
    if prompt_yes "Update argocd-image-updater-secret token?"; then
      updater_token=$(read_secret "New Argo CD API token: ")
      if [[ -n "$updater_token" ]]; then
        log "Updating argocd-image-updater-secret"
        ARGOCD_TOKEN="$updater_token" make -C "$REPO_ROOT" image-updater-secret >/dev/null
      else
        log "No token provided; keeping existing secret"
      fi
    else
      log "Keeping existing argocd-image-updater-secret"
    fi
  else
    if prompt_yes "Create argocd-image-updater-secret now?"; then
      updater_token=$(read_secret "Argo CD API token: ")
      if [[ -n "$updater_token" ]]; then
        log "Creating argocd-image-updater-secret"
        ARGOCD_TOKEN="$updater_token" make -C "$REPO_ROOT" image-updater-secret >/dev/null
      else
        log "No token provided; skipping creation"
      fi
    else
      log "Skipping argocd-image-updater-secret creation"
    fi
  fi
fi

if [[ "${FAST_PATH}" == "true" ]]; then
  log "[fast] Skipping argocd CLI repo helper (credentials provided via Secret if configured)"
elif command -v argocd >/dev/null 2>&1; then
  # Default argocd CLI options for OpenShift GitOps (requires gRPC-web)
  ARGOCD_COMMON_ARGS=(--grpc-web)
  if [[ -n "${ARGOCD_SERVER:-}" ]]; then
    ARGOCD_COMMON_ARGS+=(--server "${ARGOCD_SERVER}")
  fi
  repo_url=$GIT_REPO_URL
  log "Checking Argo CD repo credentials for $repo_url"
  if argocd repo list "${ARGOCD_COMMON_ARGS[@]}" -o name >/tmp/argocd-repo-list.$$ 2>/dev/null; then
    if grep -Fxq "$repo_url" /tmp/argocd-repo-list.$$; then
      log "Repo credential already present for $repo_url"
      if prompt_yes "Update Argo CD repo credential for $repo_url?"; then
        read -r -p "Username (leave blank if using token-only auth): " repo_user || true
        repo_pass=$(read_secret "Password/PAT (leave blank to cancel): ")
        if [[ -n "$repo_pass" ]]; then
          log "Updating repo credential"
          if [[ -n "$repo_user" ]]; then
            argocd repo add "$repo_url" --username "$repo_user" --password "$repo_pass" --upsert "${ARGOCD_COMMON_ARGS[@]}" || err "argocd repo add failed"
          else
            argocd repo add "$repo_url" --password "$repo_pass" --upsert "${ARGOCD_COMMON_ARGS[@]}" || err "argocd repo add failed"
          fi
        else
          log "No password provided; keeping existing repo credential"
        fi
      else
        log "Keeping existing repo credential"
      fi
    else
      log "Repo credential not found for $repo_url"
      if prompt_yes "Add credential for $repo_url now?"; then
        read -r -p "Username (leave blank if using token-only auth): " repo_user || true
        repo_pass=$(read_secret "Password/PAT (leave blank to cancel): ")
        if [[ -n "$repo_pass" ]]; then
          log "Adding repo credential"
          if [[ -n "$repo_user" ]]; then
            argocd repo add "$repo_url" --username "$repo_user" --password "$repo_pass" --upsert "${ARGOCD_COMMON_ARGS[@]}" || err "argocd repo add failed"
          else
            argocd repo add "$repo_url" --password "$repo_pass" --upsert "${ARGOCD_COMMON_ARGS[@]}" || err "argocd repo add failed"
          fi
        else
          log "No password provided; skipping repo add"
        fi
      elif prompt_yes "Use a different repo URL?"; then
        read -r -p "Alternate repo URL: " alt_repo || true
        if [[ -n "$alt_repo" ]]; then
          repo_url=$alt_repo
          read -r -p "Username (leave blank if using token-only auth): " repo_user || true
          repo_pass=$(read_secret "Password/PAT (leave blank to cancel): ")
          if [[ -n "$repo_pass" ]]; then
            log "Adding repo credential for $repo_url"
            if [[ -n "$repo_user" ]]; then
              argocd repo add "$repo_url" --username "$repo_user" --password "$repo_pass" --upsert "${ARGOCD_COMMON_ARGS[@]}" || err "argocd repo add failed"
            else
              argocd repo add "$repo_url" --password "$repo_pass" --upsert "${ARGOCD_COMMON_ARGS[@]}" || err "argocd repo add failed"
            fi
          else
            log "No password provided; skipping repo add"
          fi
        else
          log "No alternate URL provided; skipping"
        fi
      else
        log "Skipping repo credential creation"
      fi
    fi
  else
    err "argocd repo list failed (log in first, e.g. 'argocd login <route-host> --sso --grpc-web'). Skipping repo credential helper."
  fi
  rm -f /tmp/argocd-repo-list.$$ >/dev/null 2>&1 || true
else
  log "argocd CLI not found; skipping repo credential helper"
fi

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

refresh_app() {
  local app=$1
  if oc -n openshift-gitops get application "$app" >/dev/null 2>&1; then
    log "Forcing Argo CD refresh for $app"
    oc -n openshift-gitops annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || \
      err "Failed to annotate application $app"
  else
    log "Skipping refresh; application $app not found yet"
  fi
}

# Ensure umbrella exists, force a hard refresh, then (optionally) wait for Healthy
wait_app_present() {
  local name=$1; local ns=openshift-gitops; local timeout=${2:-300}; local interval=5; local elapsed=0
  log "Waiting for Application ${name} to be created…"
  while (( elapsed < timeout )); do
    if oc -n "$ns" get application "$name" >/dev/null 2>&1; then
      log "${name} is present"
      return 0
    fi
    sleep ${interval}; elapsed=$((elapsed+interval))
  done
  log "WARNING: ${name} not created within ${timeout}s"
  return 1
}

wait_app_present "bitiq-umbrella-$ENVIRONMENT" 300 || true
refresh_app "bitiq-umbrella-$ENVIRONMENT"
wait_app "bitiq-umbrella-$ENVIRONMENT" 600 || true
refresh_app "ci-pipelines-$ENVIRONMENT"
refresh_app "image-updater-$ENVIRONMENT"
refresh_app "toy-service-$ENVIRONMENT"
refresh_app "toy-web-$ENVIRONMENT"

wait_app "image-updater-$ENVIRONMENT" 300 || true
wait_app "ci-pipelines-$ENVIRONMENT" 300 || true
wait_app "toy-service-$ENVIRONMENT" 600 || true
wait_app "toy-web-$ENVIRONMENT" 600 || true

cat <<'EONOTES'
---
Manual follow-up:
- Expose the Tekton EventListener:
  - Dynamic DNS: choose a host port (default 8080; if busy, pick 18080)
      HOST_PORT=8080   # or 18080
      oc -n openshift-pipelines port-forward --address 0.0.0.0 svc/el-bitiq-listener ${HOST_PORT}:8080
    • Use http://<your-ddns-hostname>:${HOST_PORT} in the GitHub webhook (content type JSON, secret = github-webhook-secret)
  - or Tunnel: port-forward locally and run ngrok/cloudflared; use the tunnel URL in the GitHub webhook
- Push a commit to trigger the PipelineRun and watch with 'oc -n openshift-pipelines get pipelineruns' or 'tkn pr logs'.
- Tail argocd-image-updater logs to confirm tag detection and Git write-back.
---
EONOTES

log "Local e2e setup helper finished"
