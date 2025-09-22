#!/usr/bin/env bash
set -Eeuo pipefail

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

if [[ "$(oc auth can-i get applications.argoproj.io -n openshift-gitops)" != "yes" ]]; then
  err "User $CURRENT_USER lacks access to Argo CD Applications in openshift-gitops"
  err "Log in as kubeadmin or grant access: oc adm policy add-role-to-user admin $CURRENT_USER -n openshift-gitops"
  exit 1
fi

if [[ "$(oc auth can-i get pipelines.tekton.dev -n openshift-pipelines)" != "yes" ]]; then
  err "User $CURRENT_USER lacks access to Tekton pipelines in openshift-pipelines"
  err "Grant access: oc adm policy add-role-to-user admin $CURRENT_USER -n openshift-pipelines"
  exit 1
fi

log "Running bootstrap.sh"
ENV="$ENVIRONMENT" BASE_DOMAIN="$BASE_DOMAIN" GIT_REPO_URL="$GIT_REPO_URL" TARGET_REV="$TARGET_REV" \
  "$REPO_ROOT/scripts/bootstrap.sh"

log "Ensuring application namespace access"
oc new-project bitiq-local >/dev/null 2>&1 || true
oc -n bitiq-local create rolebinding argocd-app-admin \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller >/dev/null 2>&1 || true

log "Ensuring Tekton image namespace and permissions"
oc new-project bitiq-ci >/dev/null 2>&1 || true
oc policy add-role-to-user system:image-pusher system:serviceaccount:openshift-pipelines:pipeline -n bitiq-ci >/dev/null 2>&1 || true

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

if command -v argocd >/dev/null 2>&1; then
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

refresh_app() {
  local app=$1
  log "Forcing Argo CD refresh for $app"
  oc -n openshift-gitops annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || \
    err "Failed to annotate application $app"
}

refresh_app "ci-pipelines-$ENVIRONMENT"
refresh_app "image-updater-$ENVIRONMENT"
refresh_app "bitiq-sample-app-$ENVIRONMENT"

cat <<'EONOTES'
---
Manual follow-up:
- Expose the Tekton EventListener (port-forward svc/el-bitiq-listener and tunnel via ngrok/cloudflared).
- Add the webhook to your toy-service repo using the tunnel URL and github-webhook-secret value.
- Push a commit to trigger the PipelineRun and watch with 'oc -n openshift-pipelines get pipelineruns' or 'tkn pr logs'.
- Tail argocd-image-updater logs to confirm tag detection and Git write-back.
---
EONOTES

log "Local e2e setup helper finished"
