Title: feat(local): strfry + couchbase scaffolding, certs config, and operator bootstrap app

Summary
- Introduces initial scaffolding for strfry and Couchbase (CAO) under the Helm‑first GitOps repo, wires an umbrella Application for operator bootstrap (OLM Subscriptions), and adds local HTTPS configuration via a cert-manager config chart. Focus is ENV=local with dynamic DNS, CRC, and Vault-backed secrets.

Key Changes
- Migration plan and safety
  - docs/MIGRATION_PLAN.md: status summary, Next Actions, and milestone/task statuses
  - scripts/dev-vault.sh: non-destructive default (DEV_VAULT_OVERWRITE=never|missing|always)
  - .gitignore: ignore entire `pac-config/`
- Local runbooks
  - docs/BITIQLIVE-DEV.md: ENV=local runbook (CRC sizing, dynamic DNS, systemd crc tunnel, safe Vault seeding)
  - docs/CERTS-LOCAL.md: HTTP‑01 ClusterIssuer YAML (staging/prod), Route annotation pattern, verification
- Operator versions
  - docs/VERSION-MATRIX.md: add Couchbase Autonomous Operator (CAO) row and CSV verify command
- Charts (new)
  - charts/strfry: StatefulSet, Service, Route, PVC, values-{common,local}.yaml
  - charts/couchbase-cluster: CouchbaseCluster + CouchbaseBucket CR templates, values-{common,local}.yaml
  - charts/cert-manager-config: ClusterIssuer (HTTP‑01) with local enablement
- Umbrella and ApplicationSet wiring
  - charts/bitiq-umbrella/templates/app-strfry.yaml (gated by `strfry.enabled`)
  - charts/bitiq-umbrella/templates/app-couchbase-cluster.yaml (gated by `couchbase.enabled`)
  - charts/bitiq-umbrella/templates/app-cert-manager-config.yaml (gated by `certManager.enabled`)
  - charts/bitiq-umbrella/templates/app-bootstrap-operators.yaml (gated by `bootstrapOperators.enabled`)
  - charts/argocd-apps/templates/applicationset-umbrella.yaml: pass env flags for strfry/couchbase/cert-manager/bootstrap-operators and CAO params
  - charts/bootstrap-operators/templates/subscription-cao.yaml: CAO Subscription (disabled by default in values)

ENV=local defaults
- Enabled via ApplicationSet: strfry, couchbase, cert-manager, bootstrap-operators; CAO parameters set to typical defaults:
  - package: `couchbase-operator-certified`, catalog: `certified-operators`, channel: `stable`
- Couchbase runs as a single node (hostpath storage via empty storageClassName -> cluster default)
- Strfry exposes Route `relay.<baseDomain>`
- cert-manager installs a ClusterIssuer for HTTP‑01 (staging by default)

Verification (local)
1) Render + lint locally
   - make validate
2) Operators (post-sync)
   - oc get csv -n openshift-operators --selector=operators.coreos.com/couchbase-operator-certified.openshift-operators | rg Succeeded
   - oc api-resources | rg -i 'couchbase(cluster|bucket)'
3) Couchbase (post-sync)
   - oc get couchbasecluster -n bitiq-local
   - oc get couchbasebucket -n bitiq-local
4) Certs (HTTP‑01)
   - oc get certificates -A
   - curl -I https://relay.<your-fqdn>

Notes
- Secrets: seed via Vault (VSO) with make dev-vault; default behavior does not overwrite existing keys.
- GPU/Ollama: not included here; local uses external Ollama (no CPU mode). GPU path reserved for SNO/prod.
- CAO catalog/package/channel should be verified against your cluster and recorded in docs/VERSION-MATRIX.md if different.

Follow-ups (separate PRs recommended)
- Strfry: add ConfigMap(s) and default‑deny NetworkPolicy with explicit egress.
- Couchbase: wire VSO Secret for admin creds and (optionally) admin UI Route annotations.
- cert-manager: switch issuer to prod once staging succeeds.
- Ollama: add charts and wiring for `external|gpu` modes (no CPU mode).
- Remaining services: nostr_* charts + umbrella apps, with VSO secrets and NetworkPolicies.

Env Impact
- Affects ENV=local only (via ApplicationSet flags); sno/prod remain unchanged.

CI/Checks
- make lint, helm-unittest, and make validate pass locally.

