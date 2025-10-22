#!/usr/bin/env bash
set -Eeuo pipefail
log(){ printf '[%s] %s\n' "$(date -Ins)" "$*"; }

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR="$ROOT_DIR/.out"
mkdir -p "$OUT_DIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1"; return 1; }; }

log "Running helm lint on all charts…"
make lint

log "YAML lint (excluding Helm templates)…"
if command -v yamllint >/dev/null 2>&1; then
  files=$(git -C "$ROOT_DIR" ls-files '*.yml' '*.yaml' ':!:charts/**/templates/**')
  if [ -n "$files" ]; then
    if [ -f "$ROOT_DIR/.yamllint.yaml" ]; then
      yamllint -c "$ROOT_DIR/.yamllint.yaml" $files
    else
      yamllint $files
    fi
  else
    log "No YAML files to lint (excluding templates)."
  fi
else
  log "yamllint not found; skipping YAML lint."
fi

log "Rendering templates for each env…"
make template

render_chart() {
  local chart=$1; shift
  local outfile=$1; shift
  helm template "$chart" "$@" > "$outfile"
}

validate_file() {
  local file=$1
  if command -v kubeconform >/dev/null 2>&1; then
    kubeconform -strict -ignore-missing-schemas "$file"
  else
    log "kubeconform not found; skipping schema validation for $file"
  fi
}

policy_test() {
  local file=$1
  if command -v conftest >/dev/null 2>&1 && [ -d "$ROOT_DIR/policy" ]; then
    conftest test -p "$ROOT_DIR/policy" "$file"
  else
    log "conftest or policy/ not found; skipping policy for $file"
  fi
}

log "Render + validate: toy-service and toy-web (local, sno, prod)"
for chart in toy-service toy-web; do
  for env in local sno prod; do
    out="$OUT_DIR/${chart}-$env.yaml"
    render_chart "$ROOT_DIR/charts/${chart}" "$out" \
      -f "$ROOT_DIR/charts/${chart}/values-common.yaml" \
      -f "$ROOT_DIR/charts/${chart}/values-$env.yaml"
    validate_file "$out"
    policy_test "$out"
  done
done

log "Render + validate: argocd-apps ApplicationSet (local, sno, prod)"
for env in local sno prod; do
  out="$OUT_DIR/argocd-apps-$env.yaml"
  render_chart "$ROOT_DIR/charts/argocd-apps" "$out" --set envFilter=$env
  validate_file "$out"
  policy_test "$out"
done

log "Render + validate: vault-runtime (local, sno, prod)"
for env in local sno prod; do
  out="$OUT_DIR/vault-runtime-$env.yaml"
  app_ns="bitiq-$env"
  role="gitops-$env"
  render_chart "$ROOT_DIR/charts/vault-runtime" "$out" \
    --set enabled=true \
    --set-string vault.roleName="$role" \
    --set-string namespaces.gitops=openshift-gitops \
    --set-string namespaces.pipelines=openshift-pipelines \
    --set-string namespaces.app="$app_ns"
  validate_file "$out"
  policy_test "$out"
done

log "Render + validate: vault-config (local, sno, prod)"
for env in local sno prod; do
  out="$OUT_DIR/vault-config-$env.yaml"
  ns="bitiq-$env"
  role="gitops-$env"
  render_chart "$ROOT_DIR/charts/vault-config" "$out" \
    --set enabled=true \
    --set-string policies[0]="$role" \
    --set-string roles[0].name="$role" \
    --set-string roles[0].policies[0]="$role" \
    --set-string roles[0].targetNamespaces[0]="$ns"
  validate_file "$out"
  policy_test "$out"
done

log "Render + validate: bitiq-umbrella chart (local, sno, prod)"
for env in local sno prod; do
  out="$OUT_DIR/bitiq-umbrella-$env.yaml"
  case "$env" in
    local) base_domain="apps-crc.testing" ;;
    sno)   base_domain="apps.sno.example" ;;
    prod)  base_domain="apps.prod.example" ;;
  esac
  # Reflect env gating from charts/argocd-apps/values.yaml
  vso_enabled=false
  vco_enabled=false
  if [[ "$env" == "local" ]]; then
    vso_enabled=true
    vco_enabled=true
  fi
  render_chart "$ROOT_DIR/charts/bitiq-umbrella" "$out" \
    --set env=$env \
    --set-string baseDomain="$base_domain" \
    --set-string appNamespace="bitiq-$env" \
    --set-string repoUrl="https://github.com/bitiq-io/gitops.git" \
    --set-string targetRevision="main" \
    --set vault.runtime.enabled=$vso_enabled \
    --set vault.config.enabled=$vco_enabled
  validate_file "$out"
  policy_test "$out"
done

# ESO examples removed (T17). Validation intentionally excludes ESO to enforce VSO/VCO-only manifests.

log "Render + validate: image-updater"
out="$OUT_DIR/image-updater.yaml"
render_chart "$ROOT_DIR/charts/image-updater" "$out" --set secret.create=false
validate_file "$out"
policy_test "$out"

log "Render: ci-pipelines (Tekton CRDs; schema may be skipped)"
out="$OUT_DIR/ci-pipelines.yaml"
render_chart "$ROOT_DIR/charts/ci-pipelines" "$out"
if command -v kubeconform >/dev/null 2>&1; then
  kubeconform -strict -ignore-missing-schemas "$out" || true
fi
policy_test "$out"

log "Render: argocd-apps per env (CRDs; schema may be skipped)"
for env in local sno prod; do
  if command -v kubeconform >/dev/null 2>&1; then
    helm template "$ROOT_DIR/charts/argocd-apps" --set envFilter=$env | kubeconform -strict -ignore-missing-schemas || true
  else
    helm template "$ROOT_DIR/charts/argocd-apps" --set envFilter=$env >/dev/null
  fi
done

# Optional: shellcheck for bash scripts
if command -v shellcheck >/dev/null 2>&1; then
  log "shellcheck (scripts/*.sh)"
  shellcheck -x "$ROOT_DIR"/scripts/*.sh || true
else
  log "shellcheck not found; skipping"
fi

# DDNS sanity (offline, no AWS/network reads required)
log "DDNS updater sanity (dry-run, skip lookup)"
ROUTE53_DDNS_DEBUG=1 \
ROUTE53_DDNS_WAN_IP=203.0.113.10 \
ROUTE53_DDNS_ZONES_FILE="$ROOT_DIR/docs/examples/route53-apex-ddns.zones" \
ROUTE53_DDNS_SKIP_LOOKUP=1 \
bash -lc "$ROOT_DIR/scripts/route53-apex-ddns.sh --dry-run"

log "Validation completed."
