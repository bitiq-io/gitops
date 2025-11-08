#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENVIRONMENT=${ENV:-prod}
BASE_DOMAIN=${BASE_DOMAIN:-}

log(){ printf '[%s] %s\n' "$(date -Ins)" "$*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 1; }; }

usage(){
  cat <<EOF
prod-smoke: lightweight end-to-end checks for ENV=prod

Environment:
  ENV=prod                   # enforced
  BASE_DOMAIN=apps.<domain>  # required for prod
  BOOTSTRAP=<true|false>     # optionally run bootstrap before checks

Examples:
  ENV=prod BASE_DOMAIN=apps.prod.example \
    bash scripts/prod-smoke.sh
EOF
}

if [[ "${1:-}" =~ ^-h|--help$ ]]; then usage; exit 0; fi

need oc

if [[ "$ENVIRONMENT" != "prod" ]]; then
  echo "ENV must be prod for this wrapper (got: $ENVIRONMENT)" >&2
  exit 1
fi

if [[ -z "$BASE_DOMAIN" ]]; then
  echo "Set BASE_DOMAIN for prod (e.g., apps.prod.example)" >&2
  exit 1
fi

log "Running prod preflight checks"
BASE_DOMAIN="$BASE_DOMAIN" bash "$ROOT_DIR/scripts/prod-preflight.sh" || {
  echo "Preflight failed; fix issues above and re-run." >&2
  exit 1
}

if [[ "${BOOTSTRAP:-}" == "true" ]]; then
  log "Bootstrapping GitOps for ENV=prod"
  ENV=prod BASE_DOMAIN="$BASE_DOMAIN" bash "$ROOT_DIR/scripts/bootstrap.sh"
fi

log "Running generic smoke checks (Application health, Routes)"
ENV=prod BASE_DOMAIN="$BASE_DOMAIN" bash "$ROOT_DIR/scripts/smoke.sh" || true

ns_gitops="openshift-gitops"

log "Image Updater recent events (last 5m)"
oc -n "$ns_gitops" logs deploy/argocd-image-updater --since=5m 2>/dev/null \
  | grep -E "(Committing|Pushed change|Dry run|eligible for consideration|Setting new image)" || true

ns_app="bitiq-prod"
for route in toy-service toy-web; do
  host=$(oc -n "$ns_app" get route "$route" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$host" ]] && command -v curl >/dev/null 2>&1; then
    log "Probing $route route: https://$host"
    code=$(curl -ks -o /dev/null -w '%{http_code}' "https://$host" || true)
    log "HTTP status ($route): $code"
  fi
done

log "prod-smoke completed"
