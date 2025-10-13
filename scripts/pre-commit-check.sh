#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT_DIR"

echo "[pre-commit] lint + unit tests"
make lint
if helm plugin list 2>/dev/null | grep -q 'unittest'; then
  make hu
else
  echo "[pre-commit] helm-unittest plugin not found; skipping hu"
fi

