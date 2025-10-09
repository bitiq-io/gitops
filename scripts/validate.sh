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

log "Render: argocd-apps per env (CRDs; schema may be skipped)"
for env in local sno prod; do
  if command -v kubeconform >/dev/null 2>&1; then
    helm template "$ROOT_DIR/charts/argocd-apps" --set envFilter=$env | kubeconform -strict -ignore-missing-schemas || true
  else
    helm template "$ROOT_DIR/charts/argocd-apps" --set envFilter=$env >/dev/null
  fi
done

log "Validation completed."
