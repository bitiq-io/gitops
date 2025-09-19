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
#   CHARTS="charts/bitiq-sample-app charts/another" scripts/compute-appversion.sh <env>

here() { cd "$(dirname "$0")" && pwd -P; }
repo_root() { cd "$(here)/.." && pwd -P; }

ENV_ARG=${1:-${ENV:-local}}
ENV_NAME=${ENV_ARG}

ROOT=$(repo_root)
UMBRELLA_CHART="$ROOT/charts/bitiq-umbrella/Chart.yaml"

# Default charts to scan for image repo/tag
CHART_LIST=${CHARTS:-"charts/bitiq-sample-app"}

declare -a ENTRIES=()

for CH in ${CHART_LIST}; do
  VALUES_FILE="$ROOT/${CH}/values-${ENV_NAME}.yaml"
  if [[ ! -f "$VALUES_FILE" ]]; then
    # tolerate missing per-env overlay
    continue
  fi
  repo=""
  tag=""
  in_image=0
  while IFS= read -r line; do
    case "$line" in
      image:*) in_image=1; continue ;;
    esac
    if [[ $in_image -eq 1 ]]; then
      # Two-space indented keys under image:
      if [[ "$line" =~ ^[[:space:]]{2}repository:[[:space:]]*(.*)$ ]]; then
        repo=${BASH_REMATCH[1]}
        # strip inline comments and surrounding quotes/spaces
        repo=$(echo "$repo" | sed -E 's/[[:space:]]+#.*$//; s/^\"//; s/\"$//; s/^\x27//; s/\x27$//; s/^[[:space:]]+//; s/[[:space:]]+$//')
      elif [[ "$line" =~ ^[[:space:]]{2}tag:[[:space:]]*(.*)$ ]]; then
        tag=${BASH_REMATCH[1]}
        tag=$(echo "$tag" | sed -E 's/[[:space:]]+#.*$//; s/^\"//; s/\"$//; s/^\x27//; s/\x27$//; s/^[[:space:]]+//; s/[[:space:]]+$//')
      elif [[ ! "$line" =~ ^[[:space:]] ]]; then
        # leaving the image: block
        in_image=0
      fi
    fi
  done < "$VALUES_FILE"

  # Normalize repo/tag one more time to be safe
  repo=$(echo "$repo" | sed -E 's/^\"//; s/\"$//; s/^\x27//; s/\x27$//')
  tag=$(echo "$tag" | sed -E 's/^\"//; s/\"$//; s/^\x27//; s/\x27$//')

  if [[ -z "$repo" || -z "$tag" ]]; then
    continue
  fi

  # Derive service name from repo basename
  svc=$(basename "$repo")
  ENTRIES+=("$svc $tag")
done

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
  echo "No entries found for ENV=$ENV_NAME in CHARTS='$CHART_LIST'" >&2
  exit 1
fi

# Sort entries by service name and build composite
COMPOSITE=$(printf '%s\n' "${ENTRIES[@]}" | sort -k1,1 | awk '{printf "%s-%s_", $1, $2}' | sed 's/_$//')

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
