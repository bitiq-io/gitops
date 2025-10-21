# Migration Plan: pac-infra → bitiq-io/gitops (Final)

Owner: Paul / bitiq platform
Last updated: 2025-10-17 (status updated)

Next Actions (quick scan)
- Add bootstrap-operators to umbrella (Who: Codex). What: create `app-bootstrap-operators.yaml` to GitOps-manage OLM Subscriptions. Where: `charts/bitiq-umbrella/templates/`. Acceptance: Subscriptions render and reconcile via Argo.
- Enable CAO for local (Who: Codex). What: set `operators.cao.enabled=true` with correct `name/channel/source`. Where: `charts/bootstrap-operators/values.yaml`. Acceptance: CAO CSV Succeeded in `openshift-operators`.
- Strfry hardening (Who: Codex). What: add ConfigMap(s) and default-deny NetworkPolicy with explicit egress. Where: `charts/strfry/templates/`. Acceptance: Route OK; pods Ready; egress limited to DNS/DB.
- Couchbase wiring (Who: Codex). What: VSO Secret ref for admin creds and optional admin UI Route w/ cert-manager annotations. Where: `charts/couchbase-cluster/`; `charts/vault-runtime` values. Acceptance: cluster Ready, buckets created, admin Route HTTPS.
- Local certs verify (Who: Codex/Human). What: apply HTTP‑01 ClusterIssuer and confirm issuance end-to-end. Where: `charts/cert-manager-config/`; cluster. Acceptance: `oc get certificate` Ready; HTTPS on Routes.
- Open PR (Who: Codex). What: PR with env impact and runbooks linked. Acceptance: reviewers can reproduce local setup.

Goal
- Migrate manual OpenShift/K8s manifests and setup steps into the Helm‑first GitOps repo `bitiq-io/gitops` managed by Argo CD, with environment overlays and Vault‑backed secrets.
- Optimize for ENV=local on a remote Ubuntu home server with dynamic DNS, while keeping the structure easy to extend to ENV=prod.

Executive Summary (Local Decisions)
- Couchbase on CRC: Run CAO/Couchbase as a single‑node cluster inside CRC by default. No ODF on local; use the default hostpath storage class (by leaving `storageClassName: ""`).
- Certificates on local: Prefer cert-manager DNS‑01 with Route 53 for all public hosts, defined via Kubernetes Ingress. HTTP‑01 remains optional if TCP/80 is publicly reachable, but DNS‑01 avoids port 80 entirely and is the default for local.
- Ollama modes: No CPU mode. For ENV=local, default to `ollama.mode: external` (point at a GPU‑backed Ollama running on the Ubuntu host or another machine). Later, for SNO/prod with supported GPUs, enable GPU Operator and `ollama.mode: gpu`.
- Storage: Do not install or rely on ODF in ENV=local. Charts must support `storageClassName: ""` and minimal resource footprints.
- Security: Align with `restricted-v2` SCC defaults (runAsNonRoot, drop capabilities), readOnlyRootFilesystem where possible, and default‑deny NetworkPolicies with explicit egress.

Repo/Tooling Principles
- GitOps source of truth: All runtime manifests (except unavoidable cluster bootstrap) live in `bitiq-io/gitops` and reconcile via Argo CD.
- Helm‑first: One chart per service; env values via ApplicationSet/umbrella.
- Secrets: No clear‑text in Git. Use VSO/VCO (Vault) exclusively (ESO is removed). For local parity, seed dev secrets via `make dev-vault`.
- Dev‑Vault safety: `make dev-vault` is non‑destructive by default and will not overwrite existing Vault data. It respects env var overrides from `scripts/local-e2e-setup.sh` and supports `DEV_VAULT_OVERWRITE=never|missing|always` (default: `missing`, only adds absent keys).
- Operators: OLM Subscriptions pinned per `docs/OPERATOR-VERSIONS.md`. Do not bump channels casually.
- Validation: Keep `make validate` and `make verify-release` green locally and in CI.

Environment Model
- ENV values: `local | sno | prod` via the existing ApplicationSet/umbrella.
- Namespaces: per‑env (`bitiq-<env>`). Avoid `default`.
- Public endpoints: use Kubernetes Ingress for internet hosts. The OpenShift router serves these and creates internal Routes. Hosts come from env base domains; local uses your dynamic DNS hostname.

Status Summary
- Completed: Final plan (this file); Dev‑Vault safety (non‑destructive seeding); Local runbook; CERTS (local) doc; Strfry/Couchbase charts scaffolded; Umbrella Applications and tests; cert-manager-config chart; bootstrap-operators umbrella app; CAO wired for local via ApplicationSet; Strfry ConfigMap added; Couchbase admin VSO secret wiring added; nginx static sites converted to Ingress; cert-manager Route 53 DNS‑01 issuer with per‑zone selectors; operator recursive DNS overrides codified; Cloudflare DNS‑01 removed.
- In Progress: Operator bootstrap (CAO values verification pending), Strfry chart hardening (NetworkPolicy default‑deny rollout), Couchbase cluster wiring (optional admin ingress), cert-manager issuance verification across all public hosts.
- Pending: Ollama (external/gpu) charts, Remaining nostr_* services, Inventory doc, Validation & cutover in a live cluster.

Milestones (Updated for Local Defaults)

M0. Inventory and verification
- Status: Pending
- Snapshot current pac-config usage (do not commit it). Produce `docs/bitiq-inventory.md` listing: strfry, Couchbase (cluster/buckets), Ollama, nostr_* services, nginx, cert-manager bits, GPU prerequisites.

M1. Bootstrap operators via GitOps (OLM)
- Status: In Progress (CAO Subscription template added; values and enablement pending)
- Install via `charts/bootstrap-operators` (channels pinned):
  - OpenShift GitOps (if not already), Pipelines
  - Couchbase Autonomous Operator (enabled for local by default)
  - cert-manager (Red Hat’s operator; enabled for local by default)
  - Node Feature Discovery + GPU Operator (disabled by default for local)
- Registry creds for partner images: Prefer updating the global pull secret. If SA patching is unavoidable, gate it behind a value and document.
- Acceptance: Subscriptions reach pinned CSVs; CRDs exist; `make validate` passes.

CAO quick smoke (post-sync)
- Who: Codex agent
- What: Verify CAO CSV and CRDs installed
- Where: cluster (`openshift-operators`)
- Why: Ensure Couchbase CRs will reconcile
- Acceptance:
  - `oc get csv -n openshift-operators --selector=operators.coreos.com/couchbase-operator-certified.openshift-operators | rg Succeeded`
  - `oc api-resources | rg -i 'couchbase(cluster|bucket)'`

M2. Secrets baseline in Vault
- Status: In Progress (dev‑vault safe seeding implemented; VSO projections to be added per service)
- Seed Vault dev paths (examples):
  - `gitops/data/registry/quay` → `dockerconfigjson`
  - `gitops/data/dns/route53` or your DNS provider → credentials
  - `gitops/data/apis/openai` → `api_key`
  - `gitops/data/couchbase/admin` → `username`, `password`
- Configure VSO `VaultStaticSecret` to project into app and operator namespaces.
- Acceptance: All charts reference k8s Secrets created by VSO; no literals in values/manifests; running `make dev-vault` does not overwrite existing Vault keys unless explicitly set with `DEV_VAULT_OVERWRITE=always`.

M3. strfry chart
- Status: In Progress (StatefulSet/Service/Route/PVC done; ConfigMap added; NetworkPolicy scaffolded and disabled by default pending egress target finalization)
- New `charts/strfry/` with: ConfigMap(s), PVC (parametrized), StatefulSet (probes, resources, `restricted-v2` securityContext), Service and Route.
- Add default‑deny NetworkPolicy with explicit egress (DNS, DB, allowed APIs).
- Acceptance: Route reachable; PVC binds (`storageClassName: ""` on local); helm‑unittest and `make validate` pass.

M4. Couchbase via CAO (single‑node on CRC)
- Status: In Progress (Cluster/Buckets chart scaffolded; VSO admin Secret wiring added; optional admin Route template added; CAO operator values verification pending)
- Operator: CAO subscription enabled for local, pinned channel.
- Cluster chart: `charts/couchbase-cluster/` with:
  - Secret from Vault for admin creds (VSO‑projected)
  - `CouchbaseCluster`: size=1, hostpath default SC (leave `storageClassName` empty), OCP‑compatible securityContext
  - Memory quotas tuned for CRC; buckets parametrized per env
  - Optional admin UI Route with cert-manager annotations
- Suggested local quotas (tune as needed):
  - data: 1500Mi, index: 512Mi, query: 256Mi, search: 512Mi, eventing: 256Mi; disable analytics if tight
- Acceptance: Operator healthy; cluster forms; buckets created; apps can connect via service DNS.

Couchbase quick smoke (post-sync)
- Who: Codex agent
- What: Verify cluster/buckets CRs exist and Ready
- Where: app namespace (e.g., `bitiq-local`)
- Why: Confirm Couchbase is operational
- Acceptance:
  - `oc get couchbasecluster -n <ns>` shows a Ready cluster
  - `oc get couchbasebucket -n <ns>` lists expected buckets
  - Optional admin Route responds (if enabled)

M5. Ollama (no CPU mode)
- Status: Pending
- Modes allowed: `disabled | external | gpu` (omit CPU mode).
- Local default: `external` — point to a GPU‑backed Ollama on the Ubuntu host or another machine via values/Secret (`OLLAMA_HOST`).
- GPU path: For SNO/prod with supported NVIDIA GPUs, enable NFD + GPU Operator and deploy `charts/ollama/` (Deployment with GPU nodeSelector/tolerations, PVC, Service, optional Route).
- Acceptance: For local external mode, health checks succeed against the external Ollama; for GPU clusters, `nvidia-smi` usable and pod Ready.

M6. Remaining services (nostr_* + nginx)
- Status: Pending
- Create one chart per service; replace inline secrets with VSO‑projected Secrets; add default‑deny NetworkPolicies; image/tag parametrized.
- Add Applications under umbrella with optional Image Updater annotations.
- Acceptance: All reconcile in local; zero hardcoded secrets; `make validate` passes.

M7. cert-manager and Routes (local enabled by default)
- Status: In Progress (cert-manager-config chart added; local enablement via umbrella in place; live issuance verification pending)
- Chart: `charts/cert-manager-config/` with ClusterIssuer and DNS creds (VSO‑projected) for prod; plus an HTTP‑01 issuer for local.
- Local default: cert-manager enabled. Use HTTP‑01 with dynamic DNS:
  - Public FQDN → your WAN IP; NAT 80/443 → CRC host
  - Run `crc tunnel` as a systemd service to expose router 80/443 to the host
  - cert-manager issues real certs for Route hosts under your FQDN
- DNS‑01 alternative: Use your DNS provider API creds (e.g., Route 53) to avoid port 80 ingress.
- Acceptance: `oc get certificate` Ready; Routes terminate TLS with managed certs.

M8. Cleanups and deprecation
- Status: Pending
- Remove manual pac-config usage and live‑apply docs; link to GitOps runbooks.
- Keep `pac-config/` fully ignored in `.gitignore` to prevent accidental secret commits.

Detailed Tasks (Actionable)
Task Format: each task specifies Who, What, Where, Why, Acceptance.

1) Scaffolding
- Status: In Progress (strfry, couchbase-cluster, cert-manager-config done; others pending)
- Who: Codex agent (repo maintainer)
- What: Create charts `strfry/`, `couchbase-cluster/`, `ollama/`, `nostr-query/`, `nostr-threads/`, `nostr-thread-copier/`, `nostouch/`, `nostr-site/`, `cert-manager-config/`, `gpu/` (gpu disabled by default for local). Add umbrella `app-*.yaml` per service; add per‑service `enabled` flags in `values-local.yaml`.
- Where: `charts/*`, `charts/bitiq-umbrella/templates/app-*.yaml`
- Why: Establish GitOps structure for services and operators.
- Acceptance: `helm lint` and `make validate` pass with env filter `local`; Applications render for all new services.

2) strfry
- Status: In Progress (core resources done; ConfigMap + NetworkPolicy pending)
- Who: Codex agent (repo maintainer)
- What: Port config to ConfigMaps; add PVC; create StatefulSet with probes/securityContext (restricted‑v2), Service, Ingress; add default‑deny NetworkPolicy with explicit egress (DNS/DB).
- Where: `charts/strfry/*`, `charts/bitiq-umbrella/templates/app-strfry.yaml`
- Why: Productionize core relay; remove manual manifests.
- Acceptance: Route reachable over HTTPS in local; PVC binds with `storageClassName: ""`; validation passes.

3) Couchbase (CAO + cluster)
- Status: In Progress (chart scaffolded; operator enablement + VSO Secret wiring pending)
- Who: Codex agent (repo maintainer) + Platform admin (cluster-scoped approvals if required)
- What: Add CAO Subscription (pinned) and a `couchbase-cluster` chart: single‑node defaults on local, hostpath storage, reduced quotas; buckets parametrized; optional admin UI Ingress with cert-manager annotations.
- Where: `charts/bootstrap-operators/*`, `charts/couchbase-cluster/*`, umbrella app for Couchbase
- Why: Deterministic, GitOps-managed Couchbase replacing manual setup.
- Acceptance: Operator CSV Succeeded; cluster Ready with buckets; apps connect via service DNS; validation passes.

4) Ollama
- Status: Pending
- Who: Codex agent (repo maintainer)
- What: Add values `mode: external|gpu|disabled` (no CPU); local default `external` with `OLLAMA_HOST`; for GPU envs, add `charts/ollama/` Deployment with GPU scheduling, PVC, Service, optional Route.
- Where: `charts/ollama/*`, umbrella app
- Why: Provide embeddings without CPU mode; enable GPU deployments for SNO/prod.
- Acceptance: In local external mode, application health checks succeed against external Ollama; in GPU envs, `nvidia-smi` works and pod Ready.

5) Services (nostr_*)
- Status: Pending
- Who: Codex agent (repo maintainer)
- What: Create charts per service; switch to VSO‑projected Secrets; add default‑deny NetworkPolicies; optional Routes as needed; image/tag parametrized and optionally annotated for Image Updater.
- Where: `charts/nostr-*/`, umbrella apps
- Why: Align with GitOps structure, remove hardcoded secrets.
- Acceptance: All workloads reconcile in local; zero hardcoded secrets; validation passes.

6) cert-manager config
- Status: In Progress (chart added; enabled for local; Route 53 DNS‑01 wired)
- Who: Codex agent (repo maintainer) + Human for network/NAT
- What: Add `cert-manager-config` chart with Route 53 DNS‑01 issuer enabled by default for local; Vault‑backed AWS credentials via VSO; codify operator recursive DNS overrides; document dynamic DNS and NAT details.
- Where: `charts/cert-manager-config/*`, docs
- Why: Automated TLS in local/prod; real HTTPS on local via dynamic DNS path.
- Acceptance: `oc get certificate` shows Ready for local hosts; Ingresses terminate TLS with valid certs.

7) Docs/Runbooks
- Status: Completed (BITIQLIVE-DEV and CERTS-LOCAL added)
- Who: Codex agent (repo maintainer)
- What: Add `docs/BITIQLIVE-DEV.md` covering dynamic DNS, NAT, and `crc tunnel` service; ensure rollback procedures refer to `docs/ROLLBACK.md`.
- Where: `docs/*`
- Why: Repeatable, documented local setup and safe rollback.
- Acceptance: Docs present and referenced; developers can follow steps to reproduce local HTTPS setup.

8) Validation & Cutover
- Status: Pending
- Who: Codex agent (repo maintainer)
- What: Deploy local; confirm pods, Ingresses (HTTPS), Secrets; back up PVCs; switch DNS/CNAMEs as needed; ensure CI gates pass.
- Where: Cluster and repo CI
- Why: Verify end-to-end correctness before deprecating manual flows.
- Acceptance: Argo green; HTTPS working; CI gates green; manual pac-config instructions removed.

Prod Expansion Cheat‑Sheet
- Couchbase: increase `servers.size`, use ODF (`ocs-storagecluster-ceph-rbd/cephfs`) and proper anti‑affinity; raise quotas.
- Ollama: set `mode: gpu` and enable NFD + GPU Operator; add Machineset templates (opt‑in) under `policy/openshift-machine-api/prod/`.
- cert-manager: DNS‑01 issuer with Vault‑backed DNS creds (Route 53 in our case); ensure public hostnames (Ingress) align with prod base domain.
- Security: keep `restricted-v2`, NetworkPolicies, and readOnlyRootFilesystem where possible; add image policy/registry enforcement if required.

Appendix: Dynamic DNS + NAT quick guide (Local)
- DNS: create an A record (or CNAMEs) for your FQDN pointing to your WAN IP (update via dynamic DNS client).
- NAT: port forward 443 (and optionally 80 if using HTTP‑01) from router → Ubuntu host.
- Router exposure: either user‑space forwarding (as documented) or equivalent rules to allow the OpenShift router to serve your Ingress hosts.
- cert-manager: default to DNS‑01 (Route 53). Annotate Ingress with the ClusterIssuer; cert-manager will solve and issue real certs.

Recent Changes (2025‑10‑21)
- Cert‑manager via GitOps bootstrap: added Subscription for the OpenShift cert‑manager operator (stable‑v1) and bootstrap waits for CSV/CRDs.
- NGINX static sites under GitOps (bitiq‑local): Deployment/Service/PVC + Ingress per domain + one‑shot seeding Job; apex→www redirect handled by nginx; content served at public hosts (e.g., `www.cyphai.com`).
- Local FQDNs configured: nostr_site `alpha.cyphai.com`, strfry `relay.cyphai.com`, Couchbase admin `cb.cyphai.com` (internal app Routes remain on `apps-crc.testing`).
- Vault seeding extended: dev‑vault seeds `gitops/couchbase/admin` from `COUCHBASE_ADMIN_USERNAME/COUCHBASE_ADMIN_PASSWORD`; VSO projects to `bitiq-local/couchbase-cluster-auth`.
- Quick start (local):
  1) `ENV=local BASE_DOMAIN=apps-crc.testing VAULT_OPERATORS=true ./scripts/bootstrap.sh`
  2) `AUTO_DEV_VAULT=true ARGOCD_TOKEN='<token>' GITHUB_WEBHOOK_SECRET='<secret>' QUAY_USERNAME='<user>' QUAY_PASSWORD='<pass>' QUAY_EMAIL='<email>' COUCHBASE_ADMIN_USERNAME='Administrator' COUCHBASE_ADMIN_PASSWORD='<strong>' make dev-vault`
  3) Ensure DNS CNAMEs exist for: `alpha.cyphai.com`, `relay.cyphai.com`, `cb.cyphai.com`, `www.cyphai.com` → your DDNS host (low TTL).
  4) Refresh umbrella: `oc -n openshift-gitops annotate application bitiq-umbrella-local argocd.argoproj.io/refresh=hard --overwrite`.
  5) Verify Ingress + certs: `oc -n bitiq-local get ingress` and curl external hosts.
