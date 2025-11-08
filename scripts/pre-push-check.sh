#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT_DIR"

echo "[pre-push] validate + verify-release"
make validate
make verify-release

if [[ "${E2E_SMOKE:-}" == "1" ]]; then
  echo "[pre-push] updater E2E smoke"
  bash scripts/e2e-updater-smoke.sh
fi

