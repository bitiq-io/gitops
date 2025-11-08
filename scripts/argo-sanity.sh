#!/usr/bin/env bash
set -euo pipefail

# Argo CD diagnostics helper
# Usage:
#   ENV=local NS=openshift-gitops ./scripts/argo-sanity.sh
#   (override ENV/NS/APP via env vars as needed)

NS=${NS:-openshift-gitops}
ENV=${ENV:-local}
APP=${APP:-bitiq-umbrella-$ENV}

section() { echo "== $*"; }

section "Argo Route"
oc -n "$NS" get route openshift-gitops-server -o jsonpath='{.spec.host}{"\n"}' 2>/dev/null || echo "<missing>"

section "Argo CRDs"
oc api-resources --api-group=argoproj.io -o name 2>/dev/null | paste -sd, - || true

section "ApplicationSet conds"
oc -n "$NS" get applicationset bitiq-umbrella-by-env \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"; "}{end}{"\n"}' 2>/dev/null || echo "<not found>"

section "Umbrella spec"
oc -n "$NS" get application "$APP" \
  -o jsonpath='{.spec.source.repoURL}{" "}{.spec.source.path}{" "}{.spec.source.targetRevision}{" | auto="}{.spec.syncPolicy.automated.prune}{" "}{.spec.syncPolicy.automated.selfHeal}{"\n"}' \
  2>/dev/null || echo "$APP: <not found>"

section "Umbrella status"
oc -n "$NS" get application "$APP" \
  -o jsonpath='op={.status.operationState.phase} fin={.status.operationState.finishedAt} sync={.status.sync.status} health={.status.health.status} msg={.status.conditions[-1].message}{"\n"}' \
  2>/dev/null || true

section "Managed resources"
oc -n "$NS" get application "$APP" \
  -o jsonpath='{range .status.resources[*]}{.kind}/{.name} ns={.namespace} st={.status}{"\n"}{end}' \
  2>/dev/null || echo "<none>"

section "Applications (health/sync)"
oc -n "$NS" get application -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status --no-headers 2>/dev/null | sort || true

section "Repo Creds"
oc -n "$NS" get secret -l 'argocd.argoproj.io/secret-type in (repository,repo-creds)' \
  -o custom-columns=NAME:.metadata.name,TYPE:.metadata.labels["argocd\.argoproj\.io/secret-type"] --no-headers 2>/dev/null || true

section "Controller logs (3m, tail)"
oc -n "$NS" logs pod/openshift-gitops-application-controller-0 -c argocd-application-controller --since=3m 2>/dev/null | tail -n 120 || echo "<no controller logs>"

section "AppSet logs (3m, tail)"
oc -n "$NS" logs deploy/openshift-gitops-applicationset-controller --since=3m 2>/dev/null | tail -n 80 || echo "<no appset logs>"

