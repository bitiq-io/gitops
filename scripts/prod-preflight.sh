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
DNS_CHECK_DISABLED="${PROD_PREFLIGHT_SKIP_DNS:-false}"

require oc

failures=0
warnings=0

if ! check "Logged into cluster (oc whoami)" oc whoami >/dev/null 2>&1; then
  status INFO "Run 'oc login https://api.<cluster-domain>:6443 -u <admin>' before bootstrapping"
  ((failures++))
fi

if ! check "API reachable (oc api-resources)" oc api-resources >/dev/null 2>&1; then
  ((failures++))
fi

cluster_version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || true)
if [[ -n "$cluster_version" ]]; then
  status PASS "Cluster version: ${cluster_version}"
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 - <<'PY' >/dev/null 2>&1; then
import re
import sys

def parse(version: str):
    parts = []
    for token in version.split('.'):
        match = re.match(r'(\d+)', token)
        if match:
            parts.append(int(match.group(1)))
        else:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])

if parse("${cluster_version}") < (4, 19, 0):
    raise SystemExit(1)
PY
    then
      status WARN "Cluster version ${cluster_version} < 4.19. Review compatibility before proceeding"
      ((warnings++))
    fi
  else
    status WARN "python3 not available; skipping semantic version check"
    ((warnings++))
  fi
else
  status WARN "Unable to detect cluster version"
  ((warnings++))
fi

nodes_json=$(oc get nodes -o json 2>/dev/null || true)
if [[ -z "$nodes_json" ]]; then
  status FAIL "Unable to list nodes"
  ((failures++))
else
  control_total=0
  control_ready=0
  worker_total=0
  worker_ready=0
  ready_total=0
  if command -v python3 >/dev/null 2>&1; then
    read -r control_total control_ready worker_total worker_ready ready_total < <(
      python3 - <<'PY'
import json
import sys

data = json.load(sys.stdin)
control_total = control_ready = worker_total = worker_ready = ready_total = 0
for node in data.get("items", []):
    labels = node.get("metadata", {}).get("labels", {})
    is_control = any(key in labels for key in [
        "node-role.kubernetes.io/master",
        "node-role.kubernetes.io/control-plane",
    ])
    is_worker = "node-role.kubernetes.io/worker" in labels
    ready = False
    for cond in node.get("status", {}).get("conditions", []):
        if cond.get("type") == "Ready":
            ready = cond.get("status") == "True"
            break
    if ready:
        ready_total += 1
    if is_control:
        control_total += 1
        if ready:
            control_ready += 1
    if is_worker:
        worker_total += 1
        if ready:
            worker_ready += 1

print(control_total, control_ready, worker_total, worker_ready, ready_total)
PY
    )
  else
    status WARN "python3 missing; falling back to basic node role detection"
    control_total=$(oc get nodes --no-headers 2>/dev/null | awk '$3 ~ /master|control-plane/ {count++} END {print count+0}')
    control_ready=$(oc get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" && $3 ~ /master|control-plane/ {count++} END {print count+0}')
    worker_total=$(oc get nodes --no-headers 2>/dev/null | awk '$3 ~ /worker/ {count++} END {print count+0}')
    worker_ready=$(oc get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" && $3 ~ /worker/ {count++} END {print count+0}')
    ready_total=$(oc get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {count++} END {print count+0}')
    ((warnings++))
  fi

  status INFO "Nodes ready: ${ready_total} (control-plane ready: ${control_ready}/${control_total}, worker ready: ${worker_ready}/${worker_total})"

  if (( control_ready < 3 )); then
    status FAIL "Need at least 3 Ready control-plane nodes"
    ((failures++))
  else
    status PASS "Control-plane node count OK"
  fi

  if (( worker_ready < 2 )); then
    status FAIL "Need at least 2 Ready worker nodes"
    status INFO "Scale worker MachineSets or add worker nodes before proceeding"
    ((failures++))
  else
    status PASS "Worker node count OK"
  fi
fi

default_sc=$(oc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -n1)
if [[ -z "$default_sc" ]]; then
  status FAIL "No default StorageClass configured"
  status INFO "Install or configure a default storage class before running Tekton pipelines"
  ((failures++))
else
  status PASS "Default StorageClass: ${default_sc}"
fi

if ! oc get catalogsource -n openshift-marketplace redhat-operators >/dev/null 2>&1; then
  status WARN "CatalogSource 'redhat-operators' not reachable; mirror required operators or restore default sources"
  ((warnings++))
else
  status PASS "CatalogSource redhat-operators present"
fi

if ! oc get packagemanifest -n openshift-marketplace openshift-gitops-operator >/dev/null 2>&1; then
  status WARN "Packagemanifest 'openshift-gitops-operator' not accessible"
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

if ! check "BASE_DOMAIN environment variable set (e.g. apps.prod.example)" test -n "$BASE_DOMAIN"; then
  ((failures++))
fi

if [[ "$DNS_CHECK_DISABLED" =~ ^(true|1|yes)$ ]]; then
  status WARN "DNS check skipped (PROD_PREFLIGHT_SKIP_DNS=${DNS_CHECK_DISABLED})"
else
  if [[ -n "$BASE_DOMAIN" ]]; then
    dns_host="test.${BASE_DOMAIN}"
    if command -v python3 >/dev/null 2>&1; then
      if python3 - <<PY >/dev/null 2>&1; then
import socket
host = "${dns_host}"
socket.getaddrinfo(host, None)
PY
        status PASS "DNS resolves for wildcard (${dns_host})"
      else
        status FAIL "DNS lookup failed for ${dns_host}; configure wildcard *.${BASE_DOMAIN}"
        ((failures++))
      fi
    elif getent hosts "${dns_host}" >/dev/null 2>&1; then
      status PASS "DNS resolves for wildcard (${dns_host})"
    else
      status FAIL "DNS lookup failed for ${dns_host}; install python3 or set PROD_PREFLIGHT_SKIP_DNS=true to skip"
      ((failures++))
    fi
  fi
fi

if grep -q 'channel: latest' charts/bootstrap-operators/values.yaml; then
  status WARN "Operator channels set to 'latest'. Review and pin versions compatible with OCP 4.19"
  ((warnings++))
else
  status PASS "Operator channels appear pinned (charts/bootstrap-operators/values.yaml)"
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
