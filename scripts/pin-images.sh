#!/usr/bin/env bash
set -euo pipefail

# Pin toy-service/toy-web image tags across one or more environments and
# optionally freeze/unfreeze Argo CD Image Updater for those envs.
#
# Defaults aim for safety and determinism:
# - Updates values-<env>.yaml so Image Updater write-back remains consistent
# - Recomputes umbrella appVersion from the edited env (if all envs match,
#   verify-release passes across the board)
# - Validates tag grammar and runs verify step unless disabled
#
# Usage examples:
#   scripts/pin-images.sh --envs local,sno,prod \
#     --svc-tag v0.3.20-commit.abc1234 --web-tag v0.1.20-commit.def5678 --freeze
#
#   scripts/pin-images.sh --envs prod --svc-tag v0.3.21-commit.9999999 --no-verify
#
# Options (env vars also supported, e.g., SVC_TAG, WEB_TAG, ENVS):
#   --envs <csv>          Comma-separated envs (default: all discovered)
#   --svc-tag <tag>       toy-service tag (e.g., v0.3.20-commit.abc1234)
#   --web-tag <tag>       toy-web tag (e.g., v0.1.20-commit.def5678)
#   --svc-repo <repo>     Optional toy-service repo override
#   --web-repo <repo>     Optional toy-web repo override
#   --freeze              Set pause:true for Image Updater in env(s)
#   --unfreeze            Set pause:false for Image Updater in env(s)
#   --services <csv>      Target services (backend, frontend)
#   --backend             Shortcut for --services backend
#   --frontend            Shortcut for --services frontend
#   --no-verify           Skip verify-release checks
#   --dry-run             Print planned changes without editing files
#   --auto-commit         Create git commits without prompting
#   --auto-push           Push commits without prompting
#   --sync                Run argocd sync/wait for selected envs
#   --yes|-y              Answer yes to interactive prompts
#   --branch <name>       Target branch for push (default: current)
#   --remote <name>       Target remote (default: origin)
#   --single-commit       Use one commit instead of split freeze/tag commits
#

here() { cd "$(dirname "$0")" && pwd -P; }
ROOT=$(cd "$(here)/.." && pwd -P)

# Logging + truthiness helpers (must be defined before use)
log() { printf '[%s] %s\n' "$(date -Ins)" "$*"; }

# Return success (0) if argument looks truthy: 1|true|yes|y (case-insensitive)
# Otherwise return non-zero.
truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y) return 0 ;;
    *) return 1 ;;
  esac
}

ENVS=${ENVS:-}
# Service selection: backend (toy-service) and/or frontend (toy-web)
SERVICES=${SERVICES:-}
SVC_TAG=${SVC_TAG:-}
WEB_TAG=${WEB_TAG:-}
SVC_REPO=${SVC_REPO:-}
WEB_REPO=${WEB_REPO:-}
FREEZE=false
UNFREEZE=false
VERIFY=true
DRY_RUN=false

# Interactive/automation knobs
AUTO_COMMIT=${AUTO_COMMIT:-false}
AUTO_PUSH=${AUTO_PUSH:-false}
SYNC=${SYNC:-false}
YES=${YES:-false}
BRANCH=${BRANCH:-}
REMOTE=${REMOTE:-origin}
SPLIT_COMMITS=${SPLIT_COMMITS:-true}

TAG_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+-commit\.[0-9a-f]{7,}$'

usage() {
  sed -n '1,100p' "$0" | sed -n '1,40p' | sed 's/^# //;t;d'
}

# Define interactive helpers before any use
confirm() {
  local prompt=${1:-Continue?}
  local default=${2:-y}
  local ans
  if truthy "$YES"; then return 0; fi
  if [[ ! -t 0 ]]; then
    ans=$default
  else
    read -r -p "$prompt [$default] " ans || true
    ans=${ans:-$default}
  fi
  [[ "$ans" =~ ^[Yy]$ ]]
}

prompt() {
  local prompt=$1 def=${2:-}
  local ans
  if truthy "$YES" && [[ -n "$def" ]]; then
    echo "$def"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    if [[ -n "$def" ]]; then
      echo "$def"
    else
      echo ""
    fi
  else
    if [[ -n "$def" ]]; then
      read -r -p "$prompt [$def]: " ans || true
      echo "${ans:-$def}"
    else
      read -r -p "$prompt: " ans || true
      echo "$ans"
    fi
  fi
}

TARGET_BACKEND=false
TARGET_FRONTEND=false
PIN_BACKEND=false
PIN_FRONTEND=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --envs) ENVS=$2; shift 2 ;;
    --svc-tag) SVC_TAG=$2; shift 2 ;;
    --web-tag) WEB_TAG=$2; shift 2 ;;
    --svc-repo) SVC_REPO=$2; shift 2 ;;
    --web-repo) WEB_REPO=$2; shift 2 ;;
    --freeze) FREEZE=true; shift ;;
    --unfreeze) UNFREEZE=true; shift ;;
    --services) SERVICES=$2; shift 2 ;;
    --backend|--backend-only) TARGET_BACKEND=true; shift ;;
    --frontend|--frontend-only) TARGET_FRONTEND=true; shift ;;
    --no-verify) VERIFY=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --auto-commit) AUTO_COMMIT=true; shift ;;
    --auto-push) AUTO_PUSH=true; shift ;;
    --sync) SYNC=true; shift ;;
    --yes|-y) YES=true; shift ;;
    --branch) BRANCH=$2; shift 2 ;;
    --remote) REMOTE=$2; shift 2 ;;
    --single-commit) SPLIT_COMMITS=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Discover envs from argocd-apps values if not supplied; prompt for selection
if [[ -z "${ENVS}" ]]; then
  DISCOVERED="local,sno,prod"
  if [[ -f "$ROOT/charts/argocd-apps/values.yaml" ]]; then
    DISCOVERED=$(awk '/^- name: / {print $3}' "$ROOT/charts/argocd-apps/values.yaml" | tr -d '"' | paste -sd, -)
  fi
  if $YES; then
    ENVS="$DISCOVERED"
  else
    ENVS=$(prompt "Select envs (csv)" "local")
    ENVS=${ENVS:-local}
  fi
fi

IFS=',' read -r -a ENV_ARR <<<"$ENVS"

# Derive service selection
if [[ -n "$SERVICES" ]]; then
  IFS=',' read -r -a SVC_ARR <<<"$SERVICES"
  for s in "${SVC_ARR[@]}"; do
    case "$(echo "$s" | tr '[:upper:]' '[:lower:]')" in
      backend|svc|service|toy-service) TARGET_BACKEND=true ;;
      frontend|web|toy-web) TARGET_FRONTEND=true ;;
    esac
  done
fi
if [[ -n "$SVC_TAG" ]]; then TARGET_BACKEND=true; PIN_BACKEND=true; fi
if [[ -n "$WEB_TAG" ]]; then TARGET_FRONTEND=true; PIN_FRONTEND=true; fi

if ! truthy "$TARGET_BACKEND" && ! truthy "$TARGET_FRONTEND"; then
  TARGET_BACKEND=true
  TARGET_FRONTEND=true
fi



need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; return 1; }; }

validate_tag() {
  local tag=$1
  [[ -z "$tag" ]] && return 0
  if [[ ! $tag =~ $TAG_REGEX ]]; then
    echo "Tag '$tag' does not match required grammar vX.Y.Z-commit.<sha>" >&2
    return 1
  fi
}

current_tag() {
  local svc=$1 env=$2
  local file="$ROOT/charts/$svc/values-$env.yaml"
  [[ -f "$file" ]] || { echo ""; return 0; }
  awk -F': ' '/^[[:space:]]*tag:[[:space:]]*/ {print $2; exit}' "$file" | tr -d '"' || true
}

replace_line() {
  local file=$1 pattern=$2 new=$3
  if truthy "$DRY_RUN"; then
    log "DRY-RUN would update: $file :: s|$pattern|$new|"
    return 0
  fi
  # Use temp file to avoid in-place sed portability issues
  local tmp
  tmp=$(mktemp)
  awk -v pat="$pattern" -v repl="$new" '
    BEGIN {done=0}
    {
      if ($0 ~ pat && done==0) {
        print repl; done=1; next
      }
      print
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

update_image_file() {
  local svc=$1 env=$2 tag=$3 repo=$4
  local path="$ROOT/charts/$svc/values-$env.yaml"
  if [[ ! -f "$path" ]]; then
    log "[WARN] $path not found; skipping"
    return 0
  fi
  if [[ -n "$repo" ]]; then
    replace_line "$path" '^[[:space:]]*repository:' "  repository: $repo"
  fi
  if [[ -n "$tag" ]]; then
    replace_line "$path" '^[[:space:]]*tag:' "  tag: $tag"
  fi
}

toggle_pause_for_env() {
  local env=$1 val=$2 target=$3
  local file="$ROOT/charts/argocd-apps/values.yaml"
  [[ -f "$file" ]] || { log "[WARN] $file not found; cannot toggle pause"; return 0; }
  if truthy "$DRY_RUN"; then
    local which="both"
    if [[ "$target" == "backend" ]]; then which="backend"; fi
    if [[ "$target" == "frontend" ]]; then which="frontend"; fi
    log "DRY-RUN would set pause:$val for $which in env '$env'"
    return 0
  fi
  # Awk-based, indentation-aware replacement within the target env block
  local tmp
  tmp=$(mktemp)
  awk -v target="$env" -v newval="$val" -v which="$target" '
    function emit_pause(indent) {
      # always render with 6 spaces which matches current file formatting
      return "      pause: " newval
    }
    BEGIN {in_env=0; in_svc=0; in_web=0}
    /^\s*-\s*name:\s*/ {
      # decide if we enter or exit an env block
      in_env=($3==target)
      in_svc=0; in_web=0
      print; next
    }
    { line=$0 }
    {
      if (in_env && match($0, /^\s*toyServiceImageUpdater:/)) { in_svc=1; in_web=0; print; next }
      if (in_env && match($0, /^\s*toyWebImageUpdater:/))     { in_web=1; in_svc=0; print; next }
      if (in_env && match($0, /^\s*pause:\s*/)) {
        if ((in_svc && (which=="" || which=="both" || which=="backend")) || (in_web && (which=="" || which=="both" || which=="frontend"))) {
          print emit_pause(); next
        }
      }
      print
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Validate provided tags upfront
validate_tag "$SVC_TAG"
validate_tag "$WEB_TAG"

log "Envs: ${ENV_ARR[*]}"
targets=()
$TARGET_BACKEND && targets+=(backend)
$TARGET_FRONTEND && targets+=(frontend)
[[ ${#targets[@]} -eq 0 ]] && targets=(backend frontend)
log "Targets: ${targets[*]}"
log "Planned changes: toy-service tag='${SVC_TAG:-<no change>}' repo='${SVC_REPO:-<no change>}'; toy-web tag='${WEB_TAG:-<no change>}' repo='${WEB_REPO:-<no change>}'; freeze=$FREEZE unfreeze=$UNFREEZE verify=$VERIFY dry-run=$DRY_RUN"

if truthy "$FREEZE" && truthy "$UNFREEZE"; then
  echo "Cannot set both --freeze and --unfreeze" >&2
  exit 1
fi

declare -A SVC_TAGS WEB_TAGS

if [[ -n "$SVC_TAG" ]]; then
  for env in "${ENV_ARR[@]}"; do SVC_TAGS[$env]="$SVC_TAG"; done
  PIN_BACKEND=true
fi
if [[ -n "$WEB_TAG" ]]; then
  for env in "${ENV_ARR[@]}"; do WEB_TAGS[$env]="$WEB_TAG"; done
  PIN_FRONTEND=true
fi

PROMPT_TAGS=false
if [[ -z "$SVC_TAG" && -z "$WEB_TAG" ]]; then
  if ! truthy "$FREEZE" && ! truthy "$UNFREEZE"; then
    PROMPT_TAGS=true
  else
    if confirm "Also pin new tags during this freeze/unfreeze run?" n; then
      PROMPT_TAGS=true
    fi
  fi
fi

if $PROMPT_TAGS; then
  log "No tags provided. Enter tags to pin (leave blank to skip a service)."
  same_all=$(prompt "Use the same tags for all selected envs? (y/n)" "y")
  if [[ "$same_all" =~ ^[Yy]$ ]]; then
    if $TARGET_BACKEND; then
      hint_svc=$(current_tag toy-service "${ENV_ARR[0]}")
      tt=$(prompt "toy-service tag" "$hint_svc")
      if [[ -n "$tt" ]]; then
        validate_tag "$tt" || exit 1
        for env in "${ENV_ARR[@]}"; do SVC_TAGS[$env]="$tt"; done
        PIN_BACKEND=true
      fi
    fi
    if $TARGET_FRONTEND; then
      hint_web=$(current_tag toy-web "${ENV_ARR[0]}")
      tt=$(prompt "toy-web tag" "$hint_web")
      if [[ -n "$tt" ]]; then
        validate_tag "$tt" || exit 1
        for env in "${ENV_ARR[@]}"; do WEB_TAGS[$env]="$tt"; done
        PIN_FRONTEND=true
      fi
    fi
  else
    for env in "${ENV_ARR[@]}"; do
      if $TARGET_BACKEND; then
        hint_svc=$(current_tag toy-service "$env")
        tt=$(prompt "[$env] toy-service tag" "$hint_svc")
        if [[ -n "$tt" ]]; then
          validate_tag "$tt" || exit 1
          SVC_TAGS[$env]="$tt"
          PIN_BACKEND=true
        fi
      fi
      if $TARGET_FRONTEND; then
        hint_web=$(current_tag toy-web "$env")
        tt=$(prompt "[$env] toy-web tag" "$hint_web")
        if [[ -n "$tt" ]]; then
          validate_tag "$tt" || exit 1
          WEB_TAGS[$env]="$tt"
          PIN_FRONTEND=true
        fi
      fi
    done
    VERIFY=false
    log "Different tags per env selected; verify-release will be skipped. Chart appVersion will be computed from the first env only."
  fi
fi

RECALC=false

for env in "${ENV_ARR[@]}"; do
  env_changed=false
  if [[ -n "${SVC_TAGS[$env]:-}$SVC_REPO" ]]; then
    log "Updating toy-service values for env=$env"
    update_image_file toy-service "$env" "${SVC_TAGS[$env]:-}" "$SVC_REPO"
    env_changed=true
  fi
  if [[ -n "${WEB_TAGS[$env]:-}$WEB_REPO" ]]; then
    log "Updating toy-web values for env=$env"
    update_image_file toy-web "$env" "${WEB_TAGS[$env]:-}" "$WEB_REPO"
    env_changed=true
  fi

  if truthy "$FREEZE"; then
    log "Freezing Image Updater in env=$env"
    if $TARGET_BACKEND && $TARGET_FRONTEND; then toggle_pause_for_env "$env" true both; 
    elif $TARGET_BACKEND; then toggle_pause_for_env "$env" true backend; 
    elif $TARGET_FRONTEND; then toggle_pause_for_env "$env" true frontend; 
    else toggle_pause_for_env "$env" true both; fi
  fi
  if truthy "$UNFREEZE"; then
    log "Unfreezing Image Updater in env=$env"
    if $TARGET_BACKEND && $TARGET_FRONTEND; then toggle_pause_for_env "$env" false both; 
    elif $TARGET_BACKEND; then toggle_pause_for_env "$env" false backend; 
    elif $TARGET_FRONTEND; then toggle_pause_for_env "$env" false frontend; 
    else toggle_pause_for_env "$env" false both; fi
  fi
  if $env_changed; then
    RECALC=true
  fi
done

# Compute composite only if values changed. If tags are aligned
# across envs, verify-release will pass for all.
if ! truthy "$DRY_RUN" && truthy "$RECALC"; then
  first_env=${ENV_ARR[0]}
  log "Recomputing umbrella appVersion from ENV=$first_env"
  ENV=$first_env bash "$ROOT/scripts/compute-appversion.sh" "$first_env"
elif ! truthy "$DRY_RUN"; then
  log "No tag/repo updates detected; skipping appVersion recompute"
fi

if truthy "$VERIFY" && ! truthy "$DRY_RUN" && truthy "$RECALC"; then
  if [[ "${#ENV_ARR[@]}" -eq 3 ]]; then
    log "Running verify-release across all envs"
    bash "$ROOT/scripts/verify-release.sh"
  else
    # allow subset verification
    log "Running verify-release for envs: ${ENV_ARR[*]}"
    ENVIRONMENTS="${ENV_ARR[*]}" bash "$ROOT/scripts/verify-release.sh"
  fi
fi

git_has_changes() {
  git update-index -q --refresh || true
  ! git diff --quiet --exit-code
}

git_commit_if_any() {
  local msg=$1; shift
  local patterns=("$@")
  local files=()
  if [[ ${#patterns[@]} -gt 0 ]]; then
    # shellcheck disable=SC2068
    files=( $(git ls-files -m ${patterns[@]} 2>/dev/null || true) )
  fi
  if [[ ${#files[@]} -eq 0 ]]; then
    # Fallback: stage by patterns regardless of ls-files
    # shellcheck disable=SC2068
    git add ${patterns[@]} 2>/dev/null || true
  else
    git add "${files[@]}"
  fi
  if git_has_changes; then
    git commit -m "$msg"
    return 0
  fi
  return 1
}

maybe_auto_commit_push() {
  cd "$ROOT"
  if truthy "$DRY_RUN"; then
    log "DRY-RUN: skipping git commit/push"
    return 0
  fi

  need git || { log "git not found; skipping commit/push"; return 0; }

  # Show a concise diff summary
  log "Changed files:"; git --no-pager diff --name-only | sed 's/^/  - /'

  if ! truthy "$AUTO_COMMIT"; then
    if ! confirm "Create git commits for these changes?" y; then
      log "Skipping commit/push"
      return 0
    fi
  fi

  # Separate freeze commit if requested and present
  if truthy "$SPLIT_COMMITS" && truthy "$FREEZE"; then
    git_commit_if_any "chore(image-updater): freeze sample app updates for ${ENVS}" charts/argocd-apps/values.yaml || true
  fi

  # Commit tag + appVersion changes
  git_commit_if_any "fix(charts): pin toy-service/web tags for ${ENVS}" \
    charts/toy-service/values-*.yaml charts/toy-web/values-*.yaml charts/bitiq-umbrella/Chart.yaml || true

  if ! git_has_changes; then
    log "No further changes to commit."
  fi

  # Push if selected
  if truthy "$AUTO_PUSH" || confirm "Push to remote?" y; then
    local branch=${BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}
    local remote=${REMOTE}
    if [[ "$branch" == "HEAD" ]]; then
      branch=$(prompt "Detached HEAD; enter target branch name" "main")
      git checkout -B "$branch"
    fi
    log "Pushing to $remote $branch"
    git push -u "$remote" "$branch"
  fi
}

maybe_sync_argo() {
  if truthy "$DRY_RUN"; then
    log "DRY-RUN: skipping Argo CD sync"
    return 0
  fi
  if ! truthy "$SYNC" && ! confirm "Sync Argo CD umbrella apps now?" n; then
    return 0
  fi
  if ! need argocd; then
    log "argocd CLI not found; skipping sync"
    return 0
  fi
  for env in "${ENV_ARR[@]}"; do
    local app="bitiq-umbrella-$env"
    log "Syncing $app"
    if ! argocd app sync "$app" --retry-limit 2; then
      if ! confirm "Sync failed for $app. Continue?" n; then
        return 1
      fi
    fi
    argocd app wait "$app" --health --sync --timeout 300 || true
    argocd app get "$app" | (rg '^App Version:' || grep -E '^App Version:') || true
  done
}

maybe_unfreeze_post_sync() {
  cd "$ROOT"
  if truthy "$DRY_RUN"; then return 0; fi
  if truthy "$UNFREEZE" || (truthy "$FREEZE" && confirm "Unfreeze Image Updater now?" n); then
    for env in "${ENV_ARR[@]}"; do
      log "Unfreezing env=$env"
      if $TARGET_BACKEND && $TARGET_FRONTEND; then toggle_pause_for_env "$env" false both; 
      elif $TARGET_BACKEND; then toggle_pause_for_env "$env" false backend; 
      elif $TARGET_FRONTEND; then toggle_pause_for_env "$env" false frontend; 
      else toggle_pause_for_env "$env" false both; fi
    done
    # Commit unfreeze if any changes
    need git && git_commit_if_any "chore(image-updater): unfreeze sample app updates for ${ENVS}" charts/argocd-apps/values.yaml || true
    if truthy "$AUTO_PUSH" || confirm "Push unfreeze commit?" y; then
      local branch=${BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}
      git push -u "$REMOTE" "$branch"
    fi
  fi
}

maybe_auto_commit_push
maybe_sync_argo
maybe_unfreeze_post_sync

log "All done."
