#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] %s\n' "$(date -Ins)" "$*"
}

status() {
  local level="$1"
  shift
  log "[$level] $*"
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    status FAIL "Command '$1' not found in PATH"
    exit 1
  fi
}

check() {
  local name="$1"
  shift
  if "$@"; then
    status PASS "$name"
    return 0
  fi
  status FAIL "$name"
  return 1
}

# GitOps 1.18 supports OCP 4.14 and 4.16-4.19 per the release notes compatibility matrix.
SUPPORTED_GITOPS_MINORS=("14" "16" "17" "18" "19")
# Default minimum Ready node capacity (override with MIN_NODE_CPU/MIN_NODE_MEMORY_GIB).
MIN_NODE_CPU_CORES="${MIN_NODE_CPU:-4}"
MIN_NODE_MEMORY_GIB="${MIN_NODE_MEMORY_GIB:-16}"
SUBSCRIPTION_NAMESPACE="${SUBSCRIPTION_NAMESPACE:-openshift-operators}"

require oc
require python3

failures=0
warnings=0

if ! check "Logged into cluster (oc whoami)" oc whoami >/dev/null 2>&1; then
  status INFO "Run 'oc login https://api.<cluster-domain>:6443 -u <admin>' before running preflight"
  ((failures++))
fi

if ! check "API reachable (oc api-resources)" oc api-resources >/dev/null 2>&1; then
  ((failures++))
fi

cluster_version="$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || true)"
if [[ -n "$cluster_version" ]]; then
  status INFO "Detected OpenShift version: ${cluster_version}"
  if SUPPORTED_GITOPS_MINORS_CSV="$(IFS=,; echo "${SUPPORTED_GITOPS_MINORS[*]}")" \
     CLUSTER_VERSION="$cluster_version" python3 - <<'PY' >/dev/null 2>&1; then
import os
import re
import sys

supported = os.environ["SUPPORTED_GITOPS_MINORS_CSV"].split(",")
raw_version = os.environ["CLUSTER_VERSION"]

match = re.match(r'(?P<major>\d+)\.(?P<minor>\d+)', raw_version)
if not match:
    raise SystemExit(1)
major = match.group("major")
minor = match.group("minor")
if major != "4" or minor not in supported:
    raise SystemExit(2)
PY
  then
    status PASS "OpenShift version supported for GitOps 1.18"
  else
    status FAIL "OpenShift version ${cluster_version} not in supported range for GitOps 1.18 (expected 4.{$(IFS=,; echo "${SUPPORTED_GITOPS_MINORS[*]}")})"
    status INFO "See GitOps 1.18 compatibility matrix for supported OpenShift versions"
    ((failures++))
  fi
else
  status FAIL "Unable to determine cluster version (clusterversion 'version' missing?)"
  ((failures++))
fi

nodes_json="$(oc get nodes -o json 2>/dev/null || true)"
if [[ -z "$nodes_json" ]]; then
  status FAIL "Unable to list cluster nodes"
  ((failures++))
else
  node_report="$(MIN_NODE_CPU_CORES="$MIN_NODE_CPU_CORES" MIN_NODE_MEMORY_GIB="$MIN_NODE_MEMORY_GIB" python3 - <<'PY'
import json
import math
import os
import sys

min_cpu = float(os.environ["MIN_NODE_CPU_CORES"])
min_mem = float(os.environ["MIN_NODE_MEMORY_GIB"])

def parse_cpu(value: str) -> float:
    if value.endswith("m"):
        return float(value[:-1]) / 1000.0
    return float(value)

def parse_memory(value: str) -> float:
    units = {
        "Ki": 1 / (1024 ** 2),  # convert Ki to GiB
        "Mi": 1 / 1024,
        "Gi": 1,
        "Ti": 1024,
    }
    for suffix, multiplier in units.items():
        if value.endswith(suffix):
            number = float(value[:-len(suffix)])
            return number * multiplier
    # Assume the value is bytes if no suffix
    return float(value) / (1024 ** 3)

data = json.loads(sys.stdin.read())
items = data.get("items", [])
ready_nodes = []
for node in items:
    metadata = node.get("metadata", {})
    name = metadata.get("name", "<unknown>")
    status = node.get("status", {})
    conditions = status.get("conditions", [])
    is_ready = False
    for cond in conditions:
        if cond.get("type") == "Ready":
            is_ready = cond.get("status") == "True"
            break
    capacity = status.get("capacity", {})
    cpu = parse_cpu(capacity.get("cpu", "0"))
    memory = parse_memory(capacity.get("memory", "0"))
    ready_nodes.append((name, is_ready, cpu, memory))

ok_nodes = []
bad_nodes = []
for name, is_ready, cpu, mem in ready_nodes:
    if not is_ready:
        bad_nodes.append((name, f"Not Ready (cpu={cpu:.2f} cores, mem={mem:.1f} GiB)"))
        continue
    if cpu < min_cpu or mem < min_mem:
        bad_nodes.append((name, f"Insufficient capacity (cpu={cpu:.2f} cores, mem={mem:.1f} GiB)"))
    else:
        ok_nodes.append((name, cpu, mem))

if not ready_nodes:
    print("ERROR\tNo nodes found")
    sys.exit(1)

if bad_nodes:
    print("FAIL\t" + "; ".join(f"{name}: {msg}" for name, msg in bad_nodes))
    sys.exit(2)

names = ", ".join(f"{name} (cpu={cpu:.2f} cores, mem={mem:.1f} GiB)" for name, cpu, mem in ok_nodes)
print("PASS\t" + names)
PY
)" || true

  if [[ "$node_report" == PASS* ]]; then
    status PASS "Ready nodes meet minimum capacity (${node_report#PASS	})"
  elif [[ "$node_report" == FAIL* ]]; then
    status FAIL "Node capacity check failed: ${node_report#FAIL	}"
    ((failures++))
  else
    status FAIL "Node inspection failed: ${node_report#ERROR	}"
    ((failures++))
  fi
fi

default_sc="$(oc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -n1)"
if [[ -z "$default_sc" ]]; then
  status FAIL "No default StorageClass configured"
  status INFO "Install storage and mark a class as default (storageclass.kubernetes.io/is-default-class=true)"
  ((failures++))
else
  status PASS "Default StorageClass: ${default_sc}"
fi

check_subscription() {
  local name="$1"
  local display="$2"

  local sub_json
  sub_json="$(oc get subscription -n "${SUBSCRIPTION_NAMESPACE}" "${name}" -o json 2>/dev/null || true)"
  if [[ -z "$sub_json" ]]; then
    status FAIL "Subscription '${name}' not found in namespace ${SUBSCRIPTION_NAMESPACE}"
    ((failures++))
    return
  fi

  local result
  result="$(python3 - <<'PY'
import json
import sys

data = json.loads(sys.stdin.read())
name = data.get("metadata", {}).get("name", "<unknown>")
status = data.get("status", {})
current_csv = status.get("currentCSV") or ""
state = status.get("state") or ""
conditions = {c.get("type"): c.get("status") for c in status.get("conditions", [])}
install_applied = conditions.get("InstallPlanApplied") == "True"
install_pending = conditions.get("InstallPlanPending") == "True"

if not current_csv:
    print("FAIL\tNo currentCSV recorded")
    sys.exit(0)
if install_pending:
    print("FAIL\tInstall plan still pending")
    sys.exit(0)
if state != "AtLatestKnown":
    print(f"FAIL\tSubscription state '{state}'")
    sys.exit(0)
if not install_applied:
    print("FAIL\tInstallPlanApplied condition is not True")
    sys.exit(0)

print(f"OK\t{current_csv}")
PY
  <<<"$sub_json")"

  case "$result" in
    OK* )
      local current_csv
      current_csv="$(cut -f2 <<<"${result}" | tr -d '\r')"
      if [[ -z "$current_csv" ]]; then
        status FAIL "${display}: subscription missing current CSV"
        ((failures++))
        return
      fi
      local csv_phase
      csv_phase="$(oc get csv "$current_csv" -n "${SUBSCRIPTION_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      if [[ "$csv_phase" == "Succeeded" ]]; then
        status PASS "${display}: ${current_csv} (CSV phase Succeeded)"
      else
        status FAIL "${display}: CSV ${current_csv} not Succeeded (phase='${csv_phase}')"
        ((failures++))
      fi
      ;;
    FAIL* )
      status FAIL "${display}: ${result#FAIL	}"
      ((failures++))
      ;;
    * )
      status FAIL "${display}: unexpected subscription inspection result '${result}'"
      ((failures++))
      ;;
  esac
}

check_subscription "openshift-gitops-operator" "OpenShift GitOps subscription"
check_subscription "openshift-pipelines-operator-rh" "OpenShift Pipelines subscription"

if (( failures > 0 )); then
  status FAIL "Preflight failed (${failures} blocking issues, ${warnings} warnings)"
  exit 1
fi

if (( warnings > 0 )); then
  status WARN "Preflight completed with ${warnings} warnings"
  exit 0
fi

status PASS "Preflight checks passed"
exit 0
