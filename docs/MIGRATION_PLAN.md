# Migration Plan: pac-infra → bitiq-io/gitops (Final)

Owner: Paul / bitiq platform
Last updated: 2025-10-28 (status updated; CI/CD E2E verified for nostr_* subset)

Next Actions (quick scan)
- Persistent dev Vault (PVC‑backed, GitOps‑managed). Replace the in‑memory helper with a StatefulSet using integrated Raft storage and a bootstrap Job; wire via umbrella and pass‑through in argocd‑apps; document seeding via `vault kv put` (no secrets in Git).
- Local certs verify (Who: Codex/Human). What: apply HTTP‑01 ClusterIssuer and confirm issuance end-to-end. Where: `charts/cert-manager-config/`; cluster. Acceptance: `oc get certificate` Ready; HTTPS on Routes.
- Inventory doc (Who: Codex). What: produce `docs/bitiq-inventory.md` from current GitOps state. Acceptance: strfry, Couchbase, nostr services, nginx, GPU prerequisites documented.
- Open PR (Who: Codex). What: PR with env impact and runbooks linked. Acceptance: reviewers can reproduce local setup.

AppVersion Automation (on‑cluster) — Plan
- Why: Today the umbrella `appVersion` is a composite of image tags but is updated only when a human runs `scripts/compute-appversion.sh`. When Argo CD Image Updater writes back a new tag to any values‑<env>.yaml, `appVersion` drifts and `make verify-release` fails until it’s fixed. We want deterministic, automatic healing from inside the cluster.
- Approach: Add a small Tekton pipeline, triggered on GitHub pushes to this repo, that recomputes and commits the umbrella `appVersion` after Image Updater write‑backs. Use Vault (VSO) to supply a fine‑scoped GitHub token. Guard against loops and race conditions.

Scope & Tasks
1) Expand composite sources
   - Status: Completed (charts annotated with `bitiq.io/appversion`; compute/verify auto-discover enforces env parity for nostouch, nostr-threads, toy-service, toy-web)
   - Decision: move beyond only toy services. Include any chart that represents a rollout we care to rollback by tag.
   - Mechanism: adopt a simple opt‑in annotation on chart metadata (Chart.yaml), e.g., `annotations.bitiq.io/appversion: "true"`.
   - Update `scripts/compute-appversion.sh` to:
     - Discover charts with that annotation (fallback to `CHARTS="…"` for compatibility).
     - For each included chart, read `image.repository` and `image.tag` from `values-<env>.yaml` and build the sorted composite string.
   - Update `scripts/verify-release.sh` to use the same discovery and keep ENV parity checks.
   - Acceptance: `make verify-release` passes; composite string lists all opted‑in services (to be enumerated in follow‑up PR: nostr‑*, nostouch, strfry, etc.).

2) On‑cluster recompute job (Tekton)
   - Status: Completed (pipeline + parity sync + VSO-secret plumbing merged; next validation step is observing a live Image Updater write-back)
   - Add a Pipeline in `charts/ci-pipelines` (name: `gitops-maintenance`) with tasks:
     - `git-clone` this repo.
     - `recompute-appversion`: run `scripts/compute-appversion.sh <env>` for the envs we enforce parity on (default: local,sno,prod). If it changes Chart.yaml, stage it.
     - `verify`: run `make verify-release` (same environment policy as pre‑push).
     - `commit-and-push`: commit with a conventional message (e.g., `chore(release): recompute umbrella appVersion`) and push using a bot credential.
   - Avoid commit loops: trigger filters ignore commits authored by the bot or with the specific commit subject, and the pipeline no‑ops if only Chart.yaml changed since the last push.
   - Secrets: project a VSO‑managed secret (Vault path `gitops/github/gitops-repo`) into `openshift-pipelines` (either re‑use and copy the current `gitops-repo-creds` or add a dedicated pipelines variant). Mount into the commit step as `GIT_USERNAME/GIT_PASSWORD`.
   - Acceptance: Pushing a tag change to values‑local.yaml by Image Updater results in a follow‑up commit that updates Chart.yaml within ~1 minute without human action.

3) Triggers for this repo
   - Status: Completed (GitHub push trigger, CEL filters, and secret wiring landed; monitor initial prod run for confidence)
   - Add a TriggerTemplate/Binding/EventListener route specific to the `bitiq-io/gitops` repo (or re‑use the existing listener with a CEL filter for `repository.full_name`).
   - Filter out the recompute commit: if `head_commit.message` matches `^chore\(release\): recompute umbrella appVersion`, do nothing.
   - Acceptance: `push` to main by `argocd-image-updater` (or matching PAT user) enqueues exactly one PipelineRun; a recompute‑only commit does not re‑enqueue.

4) Env parity policy
   - Status: Completed (pipeline auto-syncs annotated chart tags using scripts/sync-env-tags.sh; LOCAL-CI-CD documents the `parity.enabled` override for intentional divergence)
   - Default: keep tags aligned across envs for the services that participate in the composite to preserve a single `appVersion` value (required by current `verify-release`).
   - Pipeline behavior: when one env’s values file changes, optionally propagate the same tag to other env overlays (config flag, default on for local until prod is active). Then recompute.
   - Document escape hatch: allow `ENVIRONMENTS=local make verify-release` locally to validate only the changed env when divergence is intended, and make the pipeline open a PR instead of pushing when envs are intentionally different.

5) Documentation & guardrails
   - Status: In Progress (LOCAL-CI-CD updated with automation notes; commitlint header limit raised to 100; remaining: dedicated runbook + rollback examples)
   - Add a docs section explaining the automation, the annotation to opt‑in charts, and how to roll back by reverting composite/app tags.
   - Add commitlint rule snippet: limit recompute headers to <=100 chars, fixed subject string to simplify trigger filters.
   - Acceptance: Runbooks updated; contributors don’t touch Chart.yaml manually.

6) Nice‑to‑have
   - Concurrency control: only one recompute PipelineRun per branch at a time (use `concurrencyPolicy`/CEL gates or a simple K8s lock via a ConfigMap).
   - Argo sync: after pushing, annotate `bitiq-umbrella-<env>` with `argocd.argoproj.io/refresh=hard` for a quicker converge in dev.
   - Observability: label recompute runs and add a short dashboard card in README linking to `tkn pr logs -L` usage.

Risks & Mitigations
- Infinite loops: avoid by filtering commit subjects/authors and by making the recompute job a no‑op when only Chart.yaml changed.
- Secret exposure: keep PAT in Vault and projected to the pipeline namespace via VSO; never commit secrets; use HTTPS basic auth with least privilege (repo:write). Rotate via Vault.
- Multi‑env collisions: we already set `envFilter=local` for CRC. The parity propagation step ensures `verify-release` remains green until we formally support env divergence.

Deliverables
- PR 1: compute/verify scripts discovery + docs.
- PR 2: Tekton pipeline/triggers + VSO secret projection to `openshift-pipelines`.
- PR 3: opt‑in annotations on selected charts and initial parity propagation (toggle documented).

Goal
- Migrate manual OpenShift/K8s manifests and setup steps into the Helm‑first GitOps repo `bitiq-io/gitops` managed by Argo CD, with environment overlays and Vault‑backed secrets.
- Optimize for ENV=local on a remote Ubuntu home server with dynamic DNS, while keeping the structure easy to extend to ENV=prod.

Executive Summary (Local Decisions)
- Couchbase on CRC: Run CAO/Couchbase as a single-node cluster inside CRC by default. No ODF on local; use the default hostpath storage class (by leaving `storageClassName: ""`). Pin Couchbase Server to 7.6.6 while CAO 2.8.1 is in use (8.0.0 is unsupported).
- Certificates on local: Prefer cert-manager DNS‑01 with Route 53 for all public hosts, defined via Kubernetes Ingress. Use a single ClusterIssuer with per‑zone solvers (zone selectors) to avoid hosted zone mismatches. HTTP‑01 remains optional if TCP/80 is publicly reachable, but DNS‑01 avoids port 80 entirely and is the default for local.
- Ollama modes: No CPU mode. For ENV=local, default to `ollama.mode: external` (point at a GPU‑backed Ollama running on the Ubuntu host or another machine). Later, for SNO/prod with supported GPUs, enable GPU Operator and `ollama.mode: gpu`.
- Storage: Do not install or rely on ODF in ENV=local. Charts must support `storageClassName: ""` and minimal resource footprints.
- Security: Align with `restricted-v2` SCC defaults (runAsNonRoot, drop capabilities), readOnlyRootFilesystem where possible, and default‑deny NetworkPolicies with explicit egress.

Repo/Tooling Principles
- GitOps source of truth: All runtime manifests (except unavoidable cluster bootstrap) live in `bitiq-io/gitops` and reconcile via Argo CD.
- Helm‑first: One chart per service; env values via ApplicationSet/umbrella.
- Secrets: No clear‑text in Git. Use VSO/VCO (Vault) exclusively (ESO is removed). For local parity, seed dev secrets via `make dev-vault`.
- Dev‑Vault safety: `make dev-vault` is non‑destructive by default and will not overwrite existing Vault data. It respects env var overrides from `scripts/local-e2e-setup.sh` and supports `DEV_VAULT_OVERWRITE=never|missing|always` (default: `missing`, only adds absent keys).
- Operators: OLM Subscriptions pinned per `docs/VERSION-MATRIX.md`. Do not bump channels casually.
- Validation: Keep `make validate` and `make verify-release` green locally and in CI.

Environment Model
- ENV values: `local | sno | prod` via the existing ApplicationSet/umbrella.
- Namespaces: per‑env (`bitiq-<env>`). Avoid `default`.
- Public endpoints: use Kubernetes Ingress for internet hosts. The OpenShift router serves these and creates internal Routes. Hosts come from env base domains; local uses your dynamic DNS hostname.

Status Summary
- Completed: Final plan (this file); Dev-Vault safety (non-destructive seeding); Local runbook; CERTS (local) doc; Strfry/Couchbase charts scaffolded; Umbrella Applications and tests; cert-manager-config chart; bootstrap-operators umbrella app; CAO wired for local via ApplicationSet; Strfry ConfigMap added with production defaults and default-deny NetworkPolicy; Couchbase admin VSO secret wiring added; nginx static sites converted to Ingress; cert-manager Route 53 DNS-01 issuer with per-zone solvers via a single ClusterIssuer; operator recursive DNS overrides codified; Cloudflare DNS-01 removed; apex DDNS script and docs added; Couchbase cluster wiring (7.6.6, operator-managed buckets, admin ingress) with VSO-projected credentials and GitOps `CouchbaseUser`/`Group`/`RoleBinding`; Ollama chart scaffolded with external + GPU modes and umbrella toggles; nostr workloads (query, threads, thread-copier, nostouch) migrated to Helm with Vault-managed secrets and network policies, and nostouch streaming validated on CRC (DNS egress requires TCP/UDP 53 and 5353).
- In Progress: Operator bootstrap (monitor CAO chart for upstream upgrades), cert-manager issuance verification across all public hosts (HTTP-01 staging issuer blocked until host 80/443 forwarder or `crc tunnel` is active; current ACME check returns connection timeout), Ollama GPU deployment validation & secret wiring.
- Pending: Inventory doc, Validation & cutover in a live cluster.

Milestones (Updated for Local Defaults)

M0. Inventory and verification
- Status: Pending
- Snapshot current pac-config usage (do not commit it). Produce `docs/bitiq-inventory.md` listing: strfry, Couchbase (cluster/buckets), Ollama, nostr_* services, nginx, cert-manager bits, GPU prerequisites.

M1. Bootstrap operators via GitOps (OLM)
- Status: Completed for local (GitOps, Pipelines, CAO Helm chart enabled, cert-manager). Monitor for upstream bumps.
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
- Status: Completed (StatefulSet hardened for `restricted-v2`, ConfigMap wiring, and default-deny NetworkPolicy with DNS/DB egress toggles merged)
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
- Status: In Progress (chart + umbrella wiring committed; external mode defaults in place; GPU deployment and health verification outstanding)
- Modes allowed: `disabled | external | gpu` (omit CPU mode).
- Local default: `external` — point to a GPU-backed Ollama on the Ubuntu host or another machine via values/Secret (`OLLAMA_HOST`).
- GPU path: For SNO/prod with supported NVIDIA GPUs, enable NFD + GPU Operator and deploy `charts/ollama/` (Deployment with GPU nodeSelector/tolerations, PVC, Service, optional Route).
- Acceptance: For local external mode, health checks succeed against the external Ollama; for GPU clusters, `nvidia-smi` usable and pod Ready.
- Notes:
  - 2025-10-24: `ollama.cyphai.com` CNAME created (Route 53 → `k7501450.eero.online` / `98.169.20.123`). Remote host now runs Ollama `v0.12.6` via systemd with `OLLAMA_HOST=0.0.0.0`; port 11434 is reachable locally but external forwarding has been removed (CRC pods need the host service or a loopback alias; HTTPS still pending if external exposure resumes).

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

Persistent Dev Vault (PVC‑backed, GitOps‑managed)
- Why: The current local helper (`scripts/dev-vault.sh`) starts Vault in dev mode (`-dev`), which is in‑memory and loses state on restart. This led to lost tokens and broken VSO/VCO flows. We need a persistent, GitOps‑managed Vault to make local CI/CD deterministic and resilient.
- What: Add a small chart to deploy a single‑node Vault server with integrated Raft storage on a PVC and a bootstrap Job to initialize once, enable Kubernetes auth, and create minimal policies/roles for VSO/VCO and apps. Keep all credentials out of Git; bootstrap generates keys at runtime and stores them only in cluster Secrets (dev‑only).

Design
- Chart: `charts/vault-dev/` (local‑only), renders:
  - Namespace‑scoped Service `vault-dev` in `vault-dev` ns, matching the current address `http://vault-dev.vault-dev.svc:8200`.
  - StatefulSet (1 replica) running `hashicorp/vault` with a `vault.hcl` ConfigMap using `storage "raft" { path = "/vault/file" }` and HTTP listener for local.
  - PVC for data (size/class configurable), probes, `restricted-v2` security context.
  - Bootstrap Job (idempotent) that:
    - Detects initialization; if not initialized, runs `vault operator init -key-shares=1 -key-threshold=1 -format=json`, saves unseal key + root token to Secret `vault-bootstrap` (dev‑only), and performs first unseal.
    - Enables KV v2 at `gitops/` mount if missing.
    - Enables/configures Kubernetes auth (`auth/kubernetes/config`) against `https://kubernetes.default.svc` with in‑pod SA JWT and CA.
    - Writes policy `gitops-local` (read/list on `gitops/*`) and role `gitops-local` binding SAs in `openshift-gitops,openshift-pipelines,bitiq-local` (parity with today’s helper).
    - Writes policy `kube-auth` and role `kube-auth` for VCO control‑plane access (AuthEngineMount/Role/Policy management), scoped to `openshift-gitops:default`.
    - Skips all steps if already initialized (Secret present) so re‑applies are no‑ops.
- Wiring:
  - `charts/argocd-apps/`: add pass‑through values `vault.server.enabled` and an Application for `charts/vault-dev` targeting `vault-dev` ns; enable for `local` only.
  - `charts/bitiq-umbrella/`: add `app-vault-dev.yaml` to deploy the new chart when `.Values.vault.server.enabled=true` and keep existing `vault.runtime.*` and `vault.config.*` pointing at `vault-dev` Service.

Migration Plan
1) Land chart and plumbing with default disabled; validate `helm template` and `make validate`.
2) Enable `vault.server.enabled=true` for `local` in argocd‑apps; push and let Argo deploy the StatefulSet side‑by‑side (same Service name for continuity).
3) When Ready, re-seed required paths via CLI only (no Git):
   - `vault kv put gitops/data/argocd/image-updater token="$ARGOCD_TOKEN"`
   - `vault kv put gitops/data/github/webhook token="$GITHUB_WEBHOOK_SECRET"`
   - `vault kv put gitops/data/registry/quay dockerconfigjson=@<(echo "$DOCKERCONFIGJSON")`
   - Any app credentials under `gitops/services/...` as documented.
   - `gitops/github/gitops-repo` **must** include `url=https://github.com/bitiq-io/gitops.git` alongside `username/password`; missing `url` causes Argo CD to ignore the credentials (regression observed 2025-10-29).
   Verify: `VaultStaticSecret` objects show Healthy in `openshift-gitops` and `openshift-pipelines`.
4) Deprecate `scripts/dev-vault.sh` in docs/Makefile; keep a thin wrapper that prints guidance and exits.

Acceptance
- `oc -n vault-dev get sts vault-dev` shows Ready; PVC bound.
- Pod restarts do not lose data; after a node/Pod restart, Vault remains initialized and data persists (first unseal handled by bootstrap only on initial init).
- VCO objects (AuthEngineMount, KubernetesAuthEngineConfig/Role, Policy) are Healthy; VSO `VaultStaticSecret` objects are Healthy and Secrets present with non‑placeholder values.
- CI/CD (Image Updater write‑back → appVersion recompute) continues to function after cluster restart.

Risks/Notes
- Dev‑only bootstrap stores unseal key and root token in a namespaced Secret for convenience. Do not expose this namespace; rotate/revoke as needed and document in runbooks. For production, use external Vault or auto‑unseal (KMS/HSM) and do not store keys in the cluster.
- Keep Service name/port stable to avoid changing consumer addresses; TLS can be introduced later if desired.

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
- Status: Completed
- Who: Codex agent (repo maintainer)
- What: Port config to ConfigMaps; add PVC; create StatefulSet with probes/securityContext (restricted‑v2), Service, Ingress; add default‑deny NetworkPolicy with explicit DNS/DB egress.
- Where: `charts/strfry/*`, `charts/bitiq-umbrella/templates/app-strfry.yaml`
- Why: Productionize core relay; remove manual manifests.
- Acceptance: Route reachable over HTTPS in local; PVC binds with `storageClassName: ""`; validation passes (met).

3) Couchbase (CAO + cluster)
- Status: In Progress (chart scaffolded; operator enablement + VSO Secret wiring pending)
- Who: Codex agent (repo maintainer) + Platform admin (cluster-scoped approvals if required)
- What: Add CAO Subscription (pinned) and a `couchbase-cluster` chart: single‑node defaults on local, hostpath storage, reduced quotas; buckets parametrized; optional admin UI Ingress with cert-manager annotations.
- Where: `charts/bootstrap-operators/*`, `charts/couchbase-cluster/*`, umbrella app for Couchbase
- Why: Deterministic, GitOps-managed Couchbase replacing manual setup.
- Acceptance: Operator CSV Succeeded; cluster Ready with buckets; apps connect via service DNS; validation passes.

4) Ollama
- Status: In Progress (chart + values scaffolded; ApplicationSet wiring added; GPU runtime validation + Vault secret projection still open)
- Who: Codex agent (repo maintainer)
- What: Add values `mode: external|gpu|disabled` (no CPU); local default `external` with `OLLAMA_HOST`; for GPU envs, add `charts/ollama/` Deployment with GPU scheduling, PVC, Service, optional Route.
- Where: `charts/ollama/*`, umbrella app
- Why: Provide embeddings without CPU mode; enable GPU deployments for SNO/prod.
- Acceptance: In local external mode, application health checks succeed against external Ollama; in GPU envs, `nvidia-smi` works and pod Ready.

5) Services (nostr_*)
- Status: Completed (nostr query/threads/thread-copier/nostouch migrated); CI/CD E2E validated for nostr-threads and nostouch
- Who: Codex agent (repo maintainer)
- What: Create charts per service; switch to VSO‑projected Secrets; add default‑deny NetworkPolicies; optional Routes as needed; image/tag parametrized and optionally annotated for Image Updater.
- Where: `charts/nostr-*/`, umbrella apps
- Why: Align with GitOps structure, remove hardcoded secrets.
- Acceptance: All workloads reconcile in local; zero hardcoded secrets; validation passes.

6) cert-manager config
- Status: In Progress (chart added; enabled for local; Route 53 DNS‑01 wired with single issuer + per‑zone solvers)
- Who: Codex agent (repo maintainer) + Human for network/NAT
- What: Add `cert-manager-config` chart with Route 53 DNS‑01 issuer enabled by default for local; Vault‑backed AWS credentials via VSO; codify operator recursive DNS overrides; document dynamic DNS and NAT details; verify HTTP‑01 staging issuer once router 80/443 forwarding is active (currently returning `urn:ietf:params:acme:error:connection` from Let’s Encrypt self-check).
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

Recent Changes (2025-10-28)
- CI/CD end-to-end validated for nostouch and nostr-threads: GitHub → Tekton Triggers EventListener → PipelineRun build/push to Quay (VSO-provisioned creds) → Argo CD Image Updater write-back to values-<env>.yaml → Argo CD sync/rollout. Port-forward/Route exposure for the EventListener confirmed per docs/LOCAL-CI-CD.md and scripts/port-forward-eventlistener.sh.

---

Recent Changes (2025-10-29)
- Vault dev cluster (vault-dev namespace) reconfigured: kubernetes auth config re-written, `kube-auth` role restored, GitOps KV seeded with PAT, and VaultStaticSecret `gitops-repo-creds` now syncs healthy in openshift-pipelines. Manual Secret removed in favour of VSO-managed projection.
- gitops-maintenance pipeline verified with pushEnabled=true (no-op commit, push stage skipped by design) — ready to push when Image Updater writes new tags.
- Planned: migrate dev Vault to a PVC-backed, GitOps-managed StatefulSet (integrated Raft storage) to eliminate in-memory loss. This plan is documented below; implementation will land behind a local-only flag and replace `scripts/dev-vault.sh`.

---

Recent Changes (2025-10-22)
- Ollama GitOps scaffolding: chart added with `external|gpu` modes, external endpoint ConfigMap, GPU Deployment + PVC/Service/Ingress/Route toggles, umbrella Application, and ApplicationSet wiring (local defaults to external).
- Cert-manager via GitOps bootstrap: added Subscription for the OpenShift cert-manager operator (stable-v1) and bootstrap waits for CSV/CRDs.
- NGINX static sites under GitOps (bitiq‑local): Deployment/Service/PVC + Ingress per domain + one‑shot seeding Job; apex→www redirect handled by nginx; content served at public hosts (e.g., `www.cyphai.com`).
- Local FQDNs configured: nostr_site `alpha.cyphai.com`, strfry `relay.cyphai.com`, Couchbase admin `cb.cyphai.com` (internal app Routes remain on `apps-crc.testing`).
- Vault seeding extended: dev‑vault seeds `gitops/couchbase/admin` from `COUCHBASE_ADMIN_USERNAME/COUCHBASE_ADMIN_PASSWORD`; VSO projects to `bitiq-local/couchbase-cluster-auth`.
- DDNS updater refined: added zones file support (`/etc/route53-apex-ddns.zones`), dry‑run and WAN IP override flags, and read‑path fallback to public DNS when IAM omits `ListResourceRecordSets`. Systemd unit examples provided under `docs/examples/systemd/`.
- Quick start (local):
  1) `ENV=local BASE_DOMAIN=apps-crc.testing VAULT_OPERATORS=true ./scripts/bootstrap.sh`
  2) `AUTO_DEV_VAULT=true ARGOCD_TOKEN='<token>' GITHUB_WEBHOOK_SECRET='<secret>' QUAY_USERNAME='<user>' QUAY_PASSWORD='<pass>' QUAY_EMAIL='<email>' COUCHBASE_ADMIN_USERNAME='Administrator' COUCHBASE_ADMIN_PASSWORD='<strong>' make dev-vault`
  3) Ensure DNS CNAMEs exist for: `alpha.cyphai.com`, `relay.cyphai.com`, `cb.cyphai.com`, `www.cyphai.com` → your DDNS host (low TTL).
  4) Refresh umbrella: `oc -n openshift-gitops annotate application bitiq-umbrella-local argocd.argoproj.io/refresh=hard --overwrite`.
  5) Verify Ingress + certs: `oc -n bitiq-local get ingress` and curl external hosts.
