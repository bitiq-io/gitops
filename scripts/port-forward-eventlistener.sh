#!/usr/bin/env bash
set -euo pipefail

OC_BIN="${OC_BIN:-oc}"
NAMESPACE="${NAMESPACE:-openshift-pipelines}"
RESOURCE="${RESOURCE:-svc/el-bitiq-listener}"
BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0}"
HOST_PORT="${HOST_PORT:-8080}"
TARGET_PORT="${TARGET_PORT:-8080}"

if ! command -v "${OC_BIN}" >/dev/null 2>&1; then
  echo "error: ${OC_BIN} not found on PATH" >&2
  exit 1
fi

exec "${OC_BIN}" -n "${NAMESPACE}" port-forward \
  --address "${BIND_ADDRESS}" \
  "${RESOURCE}" \
  "${HOST_PORT}:${TARGET_PORT}"
