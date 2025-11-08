#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] %s\n' "$(date -Ins)" "$*"
}

status() {
  local level="$1"; shift
  log "[$level] $*"
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    status FAIL "Command '$1' not found in PATH"
    exit 1
  fi
}

check() {
  local name="$1"; shift
  if "$@"; then
    status PASS "$name"
    return 0
  fi
  status FAIL "$name"
  return 1
}

BASE_DOMAIN="${BASE_DOMAIN:-}"
DNS_CHECK_DISABLED="${SNO_PREFLIGHT_SKIP_DNS:-false}"

require oc

failures=0
warnings=0

if ! check "Logged into cluster (oc whoami)" oc whoami >/dev/null 2>&1; then
  status INFO "Run 'oc login https://api.<cluster-domain>:6443 -u kubeadmin -p <password>'"
  ((failures++))
fi

if ! check "API reachable" oc api-resources >/dev/null 2>&1; then
  ((failures++))
fi

total_nodes=$(oc get nodes --no-headers 2>/dev/null | grep -c '.*' || echo 0)
ready_nodes=$(oc get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {count++} END {print count+0}' || echo 0)
if [[ "$total_nodes" != "1" ]]; then
  status FAIL "Expected exactly 1 node, found ${total_nodes}"
  ((failures++))
else
  if [[ "$ready_nodes" != "1" ]]; then
    status FAIL "Single node is not Ready"
    ((failures++))
  else
    status PASS "Single Ready node detected"
  fi
fi

default_sc=$(oc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -n1)
if [[ -z "$default_sc" ]]; then
  status FAIL "No default StorageClass configured"
  status INFO "Install OpenShift Data Foundation or LVM Storage and set a default StorageClass"
  ((failures++))
else
  status PASS "Default StorageClass: ${default_sc}"
fi

if ! oc get catalogsource -n openshift-marketplace redhat-operators >/dev/null 2>&1; then
  status WARN "CatalogSource 'redhat-operators' not reachable; mirror required Operators or restore default sources"
  ((warnings++))
else
  status PASS "CatalogSource redhat-operators present"
fi

if ! oc get packagemanifest -n openshift-marketplace openshift-gitops-operator >/dev/null 2>&1; then
  status WARN "Packagemanifest 'openshift-gitops-operator' not accessible (OperatorHub disabled or mirrored)"
  ((warnings++))
else
  status PASS "Packagemanifest openshift-gitops-operator accessible"
fi

if ! oc get packagemanifest -n openshift-marketplace openshift-pipelines-operator-rh >/dev/null 2>&1; then
  status WARN "Packagemanifest 'openshift-pipelines-operator-rh' not accessible"
  ((warnings++))
else
  status PASS "Packagemanifest openshift-pipelines-operator-rh accessible"
fi

if ! check "BASE_DOMAIN environment variable set (e.g. apps.sno.example)" test -n "$BASE_DOMAIN"; then
  ((failures++))
fi

if [[ "$DNS_CHECK_DISABLED" =~ ^(true|1|yes)$ ]]; then
  status WARN "DNS check skipped (SNO_PREFLIGHT_SKIP_DNS=${DNS_CHECK_DISABLED})"
else
  if [[ -n "$BASE_DOMAIN" ]]; then
    dns_host="test.${BASE_DOMAIN}"
    if command -v python3 >/dev/null 2>&1; then
      if python3 - <<PY >/dev/null 2>&1; then
import socket
import os
host = "${dns_host}"
try:
    socket.getaddrinfo(host, None)
except OSError:
    raise SystemExit(1)
PY
        status PASS "DNS resolves for wildcard (${dns_host})"
      else
        status FAIL "DNS lookup failed for ${dns_host}; configure wildcard *.${BASE_DOMAIN}"
        status INFO "Set wildcard DNS to the SNO node IP or add explicit hosts entries for sample Routes"
        ((failures++))
      fi
    elif getent hosts "${dns_host}" >/dev/null 2>&1; then
      status PASS "DNS resolves for wildcard (${dns_host})"
    else
      status FAIL "DNS lookup failed for ${dns_host}; configure wildcard *.${BASE_DOMAIN}"
      status INFO "Install python3 or set SNO_PREFLIGHT_SKIP_DNS=true to skip DNS check"
      ((failures++))
    fi
  fi
fi

if (( failures > 0 )); then
  status FAIL "Preflight checks failed (${failures} blocking, ${warnings} warnings)"
  exit 1
fi

if (( warnings > 0 )); then
  status WARN "Preflight completed with ${warnings} warnings"
  exit 0
fi

status PASS "Preflight completed successfully"
