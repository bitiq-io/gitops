#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
CHART_FILE="$ROOT/charts/bitiq-umbrella/Chart.yaml"
ENVIRONMENTS=${ENVIRONMENTS:-"local sno prod"}
TAG_REGEX='^[[:space:]]*tag:[[:space:]]*"?v[0-9]+\.[0-9]+\.[0-9]+-commit\.[0-9a-f]{7,}"?$'

if [[ ! -f "$CHART_FILE" ]]; then
  echo "Chart file not found at $CHART_FILE" >&2
  exit 1
fi

ACTUAL_APP_VERSION=$(awk -F'"' '/^appVersion:/ {print $2; exit}' "$CHART_FILE")
if [[ -z "${ACTUAL_APP_VERSION:-}" ]]; then
  echo "Unable to read appVersion from $CHART_FILE" >&2
  exit 1
fi

declare -i EXIT_CODE=0

check_tags() {
  local file=$1
  local env=$2
  local ok=0
  local line_number=0
  while IFS= read -r line || [[ -n $line ]]; do
    line_number=$((line_number + 1))
    if [[ $line == *"tag:"* ]]; then
      ok=1
      if [[ ! $line =~ $TAG_REGEX ]]; then
        echo "[ERROR] $file:$line_number uses non-conforming tag (env=$env): $line" >&2
        return 1
      fi
    fi
  done < "$file"
  if [[ $ok -eq 0 ]]; then
    echo "[ERROR] $file contains no tag entries (env=$env)" >&2
    return 1
  fi
  return 0
}

for ENV in $ENVIRONMENTS; do
  VALUES_FILE="$ROOT/charts/bitiq-sample-app/values-${ENV}.yaml"
  if [[ ! -f "$VALUES_FILE" ]]; then
    echo "[WARN] values file not found for ENV=$ENV ($VALUES_FILE); skipping" >&2
    continue
  fi

  if ! check_tags "$VALUES_FILE" "$ENV"; then
    EXIT_CODE=1
  fi

  EXPECTED=$(MODE=print ENV=$ENV bash "$ROOT/scripts/compute-appversion.sh" "$ENV")
  if [[ "$EXPECTED" != "$ACTUAL_APP_VERSION" ]]; then
    echo "[ERROR] Chart appVersion mismatch for ENV=$ENV" >&2
    echo "        expected: $EXPECTED" >&2
    echo "        actual:   $ACTUAL_APP_VERSION" >&2
    EXIT_CODE=1
  else
    echo "[OK] ENV=$ENV -> appVersion matches ($EXPECTED)"
  fi

done

exit $EXIT_CODE
