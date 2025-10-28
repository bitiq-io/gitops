#!/usr/bin/env bash
set -euo pipefail

# Compute a composite appVersion string for the umbrella chart based on per-env values files.
# Grammar: <svc>-vX.Y.Z-commit.<sha>_<svc2>-vA.B.C-commit.<sha>
# - svc is derived from the image repository basename (e.g., quay.io/org/toy-service -> toy-service)
# - tags are expected to look like v<semver>-commit.<shortSHA>
#
# Usage:
#   ENV=local scripts/compute-appversion.sh
#   scripts/compute-appversion.sh <env>
#
# Optional:
#   CHARTS="charts/toy-service charts/toy-web charts/another" scripts/compute-appversion.sh <env>

here() { cd "$(dirname "$0")" && pwd -P; }
repo_root() { cd "$(here)/.." && pwd -P; }

ENV_ARG=${1:-${ENV:-local}}
ENV_NAME=${ENV_ARG}
MODE=${MODE:-update}

if [[ "$MODE" != "update" && "$MODE" != "print" ]]; then
  echo "Unknown MODE='$MODE' (expected 'update' or 'print')" >&2
  exit 1
fi

ROOT=$(repo_root)
UMBRELLA_CHART="$ROOT/charts/bitiq-umbrella/Chart.yaml"

APPVERSION_ANNOTATION=${APPVERSION_ANNOTATION:-"bitiq.io/appversion"}
DEFAULT_CHARTS="charts/toy-service charts/toy-web"

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

if ((${#CHART_ARRAY[@]} == 0)); then
  echo "No charts found to compute appVersion" >&2
  exit 1
fi

echo "Computing appVersion from charts: ${CHART_ARRAY[*]}" >&2

declare -a ENTRIES=()

for CH in "${CHART_ARRAY[@]}"; do
  VALUES_FILE="$ROOT/${CH}/values-${ENV_NAME}.yaml"
  if [[ ! -f "$VALUES_FILE" ]]; then
    # tolerate missing per-env overlay
    continue
  fi
  current_repo=""
  current_tag=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*repository:[[:space:]]*(.*)$ ]]; then
      current_repo=${BASH_REMATCH[1]}
      current_repo=$(echo "$current_repo" | sed -E 's/[[:space:]]+#.*$//; s/^\"//; s/\"$//; s/^\x27//; s/\x27$//; s/^[[:space:]]+//; s/[[:space:]]+$//')
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*tag:[[:space:]]*(.*)$ ]]; then
      current_tag=${BASH_REMATCH[1]}
      current_tag=$(echo "$current_tag" | sed -E 's/[[:space:]]+#.*$//; s/^\"//; s/\"$//; s/^\x27//; s/\x27$//; s/^[[:space:]]+//; s/[[:space:]]+$//')
    fi

    if [[ -n "$current_repo" && -n "$current_tag" ]]; then
      repo=$(echo "$current_repo" | sed -E 's/^\"//; s/\"$//; s/^\x27//; s/\x27$//')
      tag=$(echo "$current_tag" | sed -E 's/^\"//; s/\"$//; s/^\x27//; s/\x27$//')
      if [[ -n "$repo" && -n "$tag" ]]; then
        svc=$(basename "$repo")
        ENTRIES+=("$svc $tag")
      fi
      current_repo=""
      current_tag=""
    fi
  done < "$VALUES_FILE"
done

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
  echo "No entries found for ENV=$ENV_NAME in CHARTS='$CHART_LIST'" >&2
  exit 1
fi

# Sort entries by service name and build composite
COMPOSITE=$(printf '%s\n' "${ENTRIES[@]}" | sort -k1,1 | awk '{printf "%s-%s_", $1, $2}' | sed 's/_$//')

if [[ "$MODE" == "print" ]]; then
  echo "$COMPOSITE"
  exit 0
fi

echo "Computed composite appVersion for ENV=${ENV_NAME}:"
echo "$COMPOSITE"

# Update umbrella Chart.yaml appVersion in place
if [[ -f "$UMBRELLA_CHART" ]]; then
  tmp=$(mktemp)
  awk -v val="$COMPOSITE" '
    BEGIN {updated=0}
    /^appVersion:/ {print "appVersion: \"" val "\""; updated=1; next}
    {print}
    END { if (updated==0) { print "appVersion: \"" val "\"" } }
  ' "$UMBRELLA_CHART" > "$tmp"
  mv "$tmp" "$UMBRELLA_CHART"
  echo "Updated $UMBRELLA_CHART with appVersion: $COMPOSITE"
else
  echo "Umbrella Chart.yaml not found at $UMBRELLA_CHART" >&2
  exit 1
fi
