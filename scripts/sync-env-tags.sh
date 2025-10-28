#!/usr/bin/env bash
set -euo pipefail

# Synchronize image tags across environment overlays for annotated charts.
# Discovers charts via the same annotation as compute-appversion.
#
# Environment:
#   ENVIRONMENTS   Space-separated list of envs (default: "local sno prod")
#   PRIMARY_ENV    Source env whose tags are authoritative (default: first in ENVIRONMENTS)
#   CHARTS         Optional explicit chart list (space-separated)
#   APPVERSION_ANNOTATION  Annotation key used to opt-in charts (default: bitiq.io/appversion)

here() { cd "$(dirname "$0")" && pwd -P; }
repo_root() { cd "$(here)/.." && pwd -P; }

ROOT=$(repo_root)
APPVERSION_ANNOTATION=${APPVERSION_ANNOTATION:-"bitiq.io/appversion"}
DEFAULT_CHARTS="charts/toy-service charts/toy-web"
ENV_LIST=${ENVIRONMENTS:-"local sno prod"}

read -r -a ENV_ARRAY <<<"${ENV_LIST}"
if [[ ${#ENV_ARRAY[@]} -eq 0 ]]; then
  echo "[sync-env-tags] No environments provided via ENVIRONMENTS" >&2
  exit 1
fi

PRIMARY_ENV=${PRIMARY_ENV:-"${ENV_ARRAY[0]}"}
if [[ -z "$PRIMARY_ENV" ]]; then
  echo "[sync-env-tags] PRIMARY_ENV is empty" >&2
  exit 1
fi

escape_regex() {
  printf '%s' "$1" | sed 's/[.[\\*^$(){}?+|/]/\\&/g'
}

discover_annotated_charts() {
  local -n _out=$1
  local pattern
  pattern=$(escape_regex "$APPVERSION_ANNOTATION")
  local chart_files=()
  mapfile -t chart_files < <(find "$ROOT/charts" -mindepth 2 -maxdepth 2 -name Chart.yaml | sort || true)
  local charts=()
  for chart_file in "${chart_files[@]}"; do
    [[ -n "$chart_file" ]] || continue
    if grep -Eq "${pattern}:[[:space:]]*\"?true\"?" "$chart_file"; then
      local chart_dir=${chart_file%/Chart.yaml}
      local rel=${chart_dir#"$ROOT"/}
      charts+=("$rel")
    fi
  done
  _out=("${charts[@]}")
}

declare -a CHART_ARRAY=()
if [[ -n "${CHARTS:-}" ]]; then
  read -r -a CHART_ARRAY <<<"${CHARTS}"
else
  discover_annotated_charts CHART_ARRAY
  if ((${#CHART_ARRAY[@]} == 0)); then
    read -r -a CHART_ARRAY <<<"${DEFAULT_CHARTS}"
  fi
fi

extract_tag() {
  local file=$1
  [[ -f "$file" ]] || return 1
  awk '
    /^[[:space:]]*#/ {next}
    {
      line=$0
      sub(/#.*/, "", line)
      if (match(line, /^[ \t]*tag:/)) {
        tag=line
        sub(/^[ \t]*tag:[ \t]*/, "", tag)
        sub(/[ \t].*/, "", tag)
        gsub(/"/, "", tag)
        gsub(/\047/, "", tag)
        if (tag != "") {
          print tag
          exit
        }
      }
    }
  ' "$file"
}

update_tag() {
  local file=$1
  local new_tag=$2
  local tmp
  tmp=$(mktemp)
  awk -v new="$new_tag" '
    BEGIN {updated=0}
    match($0, /^[[:space:]]*tag:[[:space:]]*/) && updated==0 {
      prefix=substr($0, 1, RLENGTH)
      printf "%s%s\n", prefix, new
      updated=1
      next
    }
    {print}
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

echo "[sync-env-tags] Primary env: $PRIMARY_ENV | Envs: ${ENV_ARRAY[*]} | Charts: ${CHART_ARRAY[*]}"

for CH in "${CHART_ARRAY[@]}"; do
  primary_file="$ROOT/${CH}/values-${PRIMARY_ENV}.yaml"
  if [[ ! -f "$primary_file" ]]; then
    echo "[sync-env-tags] Skipping $CH (no values-${PRIMARY_ENV}.yaml)" >&2
    continue
  fi

  primary_tag=$(extract_tag "$primary_file" || true)
  if [[ -z "$primary_tag" ]]; then
    echo "[sync-env-tags] Skipping $CH (no tag found in $primary_file)" >&2
    continue
  fi

  for ENV in "${ENV_ARRAY[@]}"; do
    [[ "$ENV" == "$PRIMARY_ENV" ]] && continue
    values_file="$ROOT/${CH}/values-${ENV}.yaml"
    if [[ ! -f "$values_file" ]]; then
      echo "[sync-env-tags] $CH lacks values-${ENV}.yaml; skipping" >&2
      continue
    fi
    current_tag=$(extract_tag "$values_file" || true)
    if [[ "$current_tag" == "$primary_tag" ]]; then
      continue
    fi
    echo "[sync-env-tags] Aligning $CH (${ENV}) tag ${current_tag:-<unset>} -> $primary_tag"
    update_tag "$values_file" "$primary_tag"
  done
done
