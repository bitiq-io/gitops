# Migration Plan: pac-infra → bitiq-io/gitops (Final)

Owner: Paul / bitiq platform
Last updated: 2025-10-17

Goal
- Migrate manual OpenShift/K8s manifests and setup steps into the Helm‑first GitOps repo `bitiq-io/gitops` managed by Argo CD, with environment overlays and Vault‑backed secrets.
- Optimize for ENV=local on a remote Ubuntu home server with dynamic DNS, while keeping the structure easy to extend to ENV=prod.

Executive Summary (Local Decisions)
- Couchbase on CRC: Run CAO/Couchbase as a single‑node cluster inside CRC by default. No ODF on local; use the default hostpath storage class (by leaving `storageClassName: ""`).
- Certificates on local: Enable cert-manager for ENV=local by default. Use HTTP‑01 solver with dynamic DNS, NAT 80/443 → CRC host, and `crc tunnel` running as a service to expose the OpenShift router. DNS‑01 is also supported if your provider has an API.
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
- Routes: use OpenShift Routes. Hosts come from env base domains; local uses your dynamic DNS hostname.

Milestones (Updated for Local Defaults)

M0. Inventory and verification
- Snapshot current pac-config usage (do not commit it). Produce `docs/bitiq-inventory.md` listing: strfry, Couchbase (cluster/buckets), Ollama, nostr_* services, nginx, cert-manager bits, GPU prerequisites.

M1. Bootstrap operators via GitOps (OLM)
- Install via `charts/bootstrap-operators` (channels pinned):
  - OpenShift GitOps (if not already), Pipelines
  - Couchbase Autonomous Operator (enabled for local by default)
  - cert-manager (Red Hat’s operator; enabled for local by default)
  - Node Feature Discovery + GPU Operator (disabled by default for local)
- Registry creds for partner images: Prefer updating the global pull secret. If SA patching is unavoidable, gate it behind a value and document.
- Acceptance: Subscriptions reach pinned CSVs; CRDs exist; `make validate` passes.

M2. Secrets baseline in Vault
- Seed Vault dev paths (examples):
  - `gitops/data/registry/quay` → `dockerconfigjson`
  - `gitops/data/dns/route53` or your DNS provider → credentials
  - `gitops/data/apis/openai` → `api_key`
  - `gitops/data/couchbase/admin` → `username`, `password`
- Configure VSO `VaultStaticSecret` to project into app and operator namespaces.
- Acceptance: All charts reference k8s Secrets created by VSO; no literals in values/manifests; running `make dev-vault` does not overwrite existing Vault keys unless explicitly set with `DEV_VAULT_OVERWRITE=always`.

M3. strfry chart
- New `charts/strfry/` with: ConfigMap(s), PVC (parametrized), StatefulSet (probes, resources, `restricted-v2` securityContext), Service and Route.
- Add default‑deny NetworkPolicy with explicit egress (DNS, DB, allowed APIs).
- Acceptance: Route reachable; PVC binds (`storageClassName: ""` on local); helm‑unittest and `make validate` pass.

M4. Couchbase via CAO (single‑node on CRC)
- Operator: CAO subscription enabled for local, pinned channel.
- Cluster chart: `charts/couchbase-cluster/` with:
  - Secret from Vault for admin creds (VSO‑projected)
  - `CouchbaseCluster`: size=1, hostpath default SC (leave `storageClassName` empty), OCP‑compatible securityContext
  - Memory quotas tuned for CRC; buckets parametrized per env
  - Optional admin UI Route with cert-manager annotations
- Suggested local quotas (tune as needed):
  - data: 1500Mi, index: 512Mi, query: 256Mi, search: 512Mi, eventing: 256Mi; disable analytics if tight
- Acceptance: Operator healthy; cluster forms; buckets created; apps can connect via service DNS.

M5. Ollama (no CPU mode)
- Modes allowed: `disabled | external | gpu` (omit CPU mode).
- Local default: `external` — point to a GPU‑backed Ollama on the Ubuntu host or another machine via values/Secret (`OLLAMA_HOST`).
- GPU path: For SNO/prod with supported NVIDIA GPUs, enable NFD + GPU Operator and deploy `charts/ollama/` (Deployment with GPU nodeSelector/tolerations, PVC, Service, optional Route).
- Acceptance: For local external mode, health checks succeed against the external Ollama; for GPU clusters, `nvidia-smi` usable and pod Ready.

M6. Remaining services (nostr_* + nginx)
- Create one chart per service; replace inline secrets with VSO‑projected Secrets; add default‑deny NetworkPolicies; image/tag parametrized.
- Add Applications under umbrella with optional Image Updater annotations.
- Acceptance: All reconcile in local; zero hardcoded secrets; `make validate` passes.

M7. cert-manager and Routes (local enabled by default)
- Chart: `charts/cert-manager-config/` with ClusterIssuer and DNS creds (VSO‑projected) for prod; plus an HTTP‑01 issuer for local.
- Local default: cert-manager enabled. Use HTTP‑01 with dynamic DNS:
  - Public FQDN → your WAN IP; NAT 80/443 → CRC host
  - Run `crc tunnel` as a systemd service to expose router 80/443 to the host
  - cert-manager issues real certs for Route hosts under your FQDN
- DNS‑01 alternative: Use provider API creds if available (e.g., Route53/Cloudflare) to avoid port 80 ingress.
- Acceptance: `oc get certificate` Ready; Routes terminate TLS with managed certs.

M8. Cleanups and deprecation
- Remove manual pac-config usage and live‑apply docs; link to GitOps runbooks.
- Keep `pac-config/` fully ignored in `.gitignore` to prevent accidental secret commits.

Detailed Tasks (Actionable)
Task Format: each task specifies Who, What, Where, Why, Acceptance.

1) Scaffolding
- Who: Codex agent (repo maintainer)
- What: Create charts `strfry/`, `couchbase-cluster/`, `ollama/`, `nostr-query/`, `nostr-threads/`, `nostr-thread-copier/`, `nostouch/`, `nostr-site/`, `cert-manager-config/`, `gpu/` (gpu disabled by default for local). Add umbrella `app-*.yaml` per service; add per‑service `enabled` flags in `values-local.yaml`.
- Where: `charts/*`, `charts/bitiq-umbrella/templates/app-*.yaml`
- Why: Establish GitOps structure for services and operators.
- Acceptance: `helm lint` and `make validate` pass with env filter `local`; Applications render for all new services.

2) strfry
- Who: Codex agent (repo maintainer)
- What: Port config to ConfigMaps; add PVC; create StatefulSet with probes/securityContext (restricted‑v2), Service, Route; add default‑deny NetworkPolicy with explicit egress (DNS/DB).
- Where: `charts/strfry/*`, `charts/bitiq-umbrella/templates/app-strfry.yaml`
- Why: Productionize core relay; remove manual manifests.
- Acceptance: Route reachable over HTTPS in local; PVC binds with `storageClassName: ""`; validation passes.

3) Couchbase (CAO + cluster)
- Who: Codex agent (repo maintainer) + Platform admin (cluster-scoped approvals if required)
- What: Add CAO Subscription (pinned) and a `couchbase-cluster` chart: single‑node defaults on local, hostpath storage, reduced quotas; buckets parametrized; optional admin UI Route with cert-manager annotations.
- Where: `charts/bootstrap-operators/*`, `charts/couchbase-cluster/*`, umbrella app for Couchbase
- Why: Deterministic, GitOps-managed Couchbase replacing manual setup.
- Acceptance: Operator CSV Succeeded; cluster Ready with buckets; apps connect via service DNS; validation passes.

4) Ollama
- Who: Codex agent (repo maintainer)
- What: Add values `mode: external|gpu|disabled` (no CPU); local default `external` with `OLLAMA_HOST`; for GPU envs, add `charts/ollama/` Deployment with GPU scheduling, PVC, Service, optional Route.
- Where: `charts/ollama/*`, umbrella app
- Why: Provide embeddings without CPU mode; enable GPU deployments for SNO/prod.
- Acceptance: In local external mode, application health checks succeed against external Ollama; in GPU envs, `nvidia-smi` works and pod Ready.

5) Services (nostr_*)
- Who: Codex agent (repo maintainer)
- What: Create charts per service; switch to VSO‑projected Secrets; add default‑deny NetworkPolicies; optional Routes as needed; image/tag parametrized and optionally annotated for Image Updater.
- Where: `charts/nostr-*/`, umbrella apps
- Why: Align with GitOps structure, remove hardcoded secrets.
- Acceptance: All workloads reconcile in local; zero hardcoded secrets; validation passes.

6) cert-manager config
- Who: Codex agent (repo maintainer) + Human for network/NAT
- What: Add `cert-manager-config` chart with local HTTP‑01 issuer enabled by default; prod DNS‑01 issuer with Vault‑backed creds; document dynamic DNS, NAT 80/443→CRC host, and `crc tunnel` systemd service.
- Where: `charts/cert-manager-config/*`, docs
- Why: Automated TLS in local/prod; real HTTPS on local via dynamic DNS path.
- Acceptance: `oc get certificate` shows Ready for local hosts; Routes terminate TLS with valid certs.

7) Docs/Runbooks
- Who: Codex agent (repo maintainer)
- What: Add `docs/BITIQLIVE-DEV.md` covering dynamic DNS, NAT, and `crc tunnel` service; ensure rollback procedures refer to `docs/ROLLBACK.md`.
- Where: `docs/*`
- Why: Repeatable, documented local setup and safe rollback.
- Acceptance: Docs present and referenced; developers can follow steps to reproduce local HTTPS setup.

8) Validation & Cutover
- Who: Codex agent (repo maintainer)
- What: Deploy local; confirm pods, Routes (HTTPS), Secrets; back up PVCs; switch DNS to new Routes as needed; ensure CI gates pass.
- Where: Cluster and repo CI
- Why: Verify end-to-end correctness before deprecating manual flows.
- Acceptance: Argo green; HTTPS working; CI gates green; manual pac-config instructions removed.

Prod Expansion Cheat‑Sheet
- Couchbase: increase `servers.size`, use ODF (`ocs-storagecluster-ceph-rbd/cephfs`) and proper anti‑affinity; raise quotas.
- Ollama: set `mode: gpu` and enable NFD + GPU Operator; add Machineset templates (opt‑in) under `policy/openshift-machine-api/prod/`.
- cert-manager: switch to DNS‑01 issuer with Vault‑backed DNS creds; ensure Route hosts align with prod base domain.
- Security: keep `restricted-v2`, NetworkPolicies, and readOnlyRootFilesystem where possible; add image policy/registry enforcement if required.

Appendix: Dynamic DNS + `crc tunnel` quick guide (Local)
- DNS: create an A record for your FQDN pointing to your WAN IP (update via your dynamic DNS client).
- NAT: port forward 80 and 443 from router → Ubuntu host.
- `crc tunnel`: create a systemd service running `crc tunnel` to expose CRC router on 80/443; ensure it starts on boot and restarts on failure.
- cert-manager: configure HTTP‑01 issuer; create Routes with hosts under your FQDN; cert-manager will solve and issue real certs.
