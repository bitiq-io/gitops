# Bitiq GitOps Inventory (2025-10)

This inventory summarizes the workloads, critical operators, and secret flows that are already codified in `bitiq-io/gitops`. It is derived from the MIGRATION_PLAN, the Helm charts under `charts/`, and the supporting docs (LOCAL-CI-CD, PROD-SECRETS, VAULT-* runbooks). The focus is ENV=local because it is the only fully enabled environment today, but every entry calls out the knobs needed for `sno`/`prod`.

> Update this document whenever you add a chart, touch the Vault plumbing, or change how a public host is served. It is the human-readable index that reviewers expect when we say “GitOps is the source of truth.”

## Platform & Operators

### Bootstrap operators

- Managed via `charts/bootstrap-operators` and turned on by `charts/argocd-apps` per env.
- Local defaults (see `charts/argocd-apps/values.yaml:17-87`) enable:
  - OpenShift GitOps 1.18 (cluster-scoped instance, controller SA `openshift-gitops-argocd-application-controller`).
  - OpenShift Pipelines 1.20.
  - Vault Secrets Operator (VSO) + Vault Config Operator (VCO).
  - cert-manager operator (`stable-v1` channel).
  - Couchbase Autonomous Operator (CAO) when `caoEnabled=true`.
- Node Feature Discovery + GPU Operator are available but left disabled in local overlays; flip the relevant `bootstrapOperators` flags when preparing SNO/prod GPU nodes.

### Vault footprint

- `charts/vault-dev/` provides the persistent Raft-backed dev Vault in namespace `vault-dev` (Service `vault-dev.vault-dev.svc:8200`). The bootstrap Job seeds Kubernetes auth (`kube-auth`) and writes the dev recovery secret (`vault-bootstrap`).
- `charts/vault-config/` and `charts/vault-runtime/` render VCO + VSO resources respectively. Umbrella values wire them through `vault.config.*` and `vault.runtime.*` per env (`charts/argocd-apps/values.yaml:30-63` for local).
- Runtime secrets (see `charts/vault-runtime/values.yaml`) currently managed for every env:

| Vault path (under `gitops/data/…`) | Kubernetes Secret | Namespace | Consumer(s) |
| --- | --- | --- | --- |
| `argocd/image-updater` | `argocd-image-updater-secret` | `openshift-gitops` | Argo CD Image Updater write-back PAT |
| `registry/quay` | `quay-auth` (`dockerconfigjson`) | `openshift-pipelines` | Tekton `pipeline` SA + Image Updater |
| `github/webhook` | `github-webhook-secret` | `openshift-pipelines` | Tekton EventListener interceptor |
| `github/gitops-repo` | `gitops-repo-creds` | `openshift-gitops`, `openshift-pipelines` | Argo CD + Tekton clones/pushes |
| `services/toy-service/config` | `toy-service-config` | `bitiq-<env>` | Sample backend env vars (rollout restarts enabled) |
| `services/toy-web/config` | `toy-web-config` | `bitiq-<env>` | Sample frontend env vars |
| `couchbase/admin` | `couchbase-cluster-auth` | `bitiq-<env>` | CAO + nostr workloads |
| `services/nostr-query/credentials` | `nostr-query-credentials` | `bitiq-<env>` | OPENAI API key consumed by nostr-query |
| `cert-manager/route53` (optional) | `route53-credentials` | `cert-manager` | DNS-01 ClusterIssuer credentials |

Seed/rotate every entry through Vault (never via `oc create secret`). `make dev-vault` hydrates the local Vault using the env vars described in `docs/VAULT-DEV-RECOVERY-PLAN.md`.

### cert-manager configuration

- Chart: `charts/cert-manager-config/` (enabled for `local`).
- HTTP-01 issuer (`letsencrypt-http01-local`) defaults to staging until TCP/80 forwarding is verified.
- DNS-01 issuer (`letsencrypt-dns01-route53-local`) is active today with per-zone solvers for `cyphai.com`, `didgo.com`, `paulcapestany.com`, `bitiq.io`, `noelcapestany.com`, `beatricecapestany.com`, `ipiqi.com`, `neuance.net`, `signet.ing` (see `values-local.yaml`).
- Operator override sets recursive resolvers to Cloudflare + Google, and an upstream resolver chain keeps `*.apps-crc.testing` reachable from pods.
- `route53-credentials` comes from Vault (`gitops/data/cert-manager/route53`) and is projected into the `cert-manager` namespace via VSO.

### CI/CD & automation highlights

- Argo CD umbrella (`charts/bitiq-umbrella/`) and ApplicationSet (`charts/argocd-apps/`) are the only sources of truth for workloads.
- Tekton pipelines live under `charts/ci-pipelines`; `make local-e2e` documents the CRC workflow in `docs/LOCAL-CI-CD.md`.
- AppVersion automation: Tekton `gitops-maintenance` pipeline recomputes umbrella `appVersion` whenever Image Updater writes back a tag.

## Workload Inventory

### Strfry (Nostr relay)

- Chart: `charts/strfry/` with `values-local.yaml` overriding PVC size and Route host.
- Enabled via umbrella flag `strfry.enabled` / `strfryEnabled` (Argo Application `app-strfry.yaml`).
- Namespace: `bitiq-<env>`; service mesh: Deployment → StatefulSet (1 replica), PVC (`10Gi`, hostpath on CRC), Service (`ClusterIP`), OpenShift Route `relay.cyphai.com` (TLS managed by cert-manager DNS-01).
- Configuration: `config.strfryConf` and `config.routerConf` render ConfigMaps containing the relay + router config. DNS policy is `None` with explicit resolvers (1.1.1.1, 8.8.8.8) to avoid CRC DNS drift.
- NetworkPolicy: default deny with DNS egress, Couchbase egress (ports 8091/11210/18091/18096), and external HTTPS egress for upstream relays.
- Secrets: none; all state is on PVC. Vault only participates indirectly (downstream workloads reuse the Couchbase secret).

### Couchbase Autonomous Operator + Cluster

- Operators: enable CAO via `bootstrapOperators.cao*` in the umbrella values; CAO subscription lands in `openshift-operators`.
- Chart: `charts/couchbase-cluster/` renders the `CouchbaseCluster`, optional admin Route/Ingress, user/bucket CRs, and depends on `couchbase-cluster-auth` (Vault).
- Local defaults:
  - Single node (`servers.size=1`), services = data/index/query/search/eventing, hostpath storage (empty `storageClass*`).
  - Buckets: `all-nostr-events` (512Mi, high priority), `dev-threads`, `dev-eventing-threads`, `dev-eventing-nostr-ai` (see `values-local.yaml`).
  - Admin ingress + Route host `cb.cyphai.com` with TLS via HTTP-01/DNS-01 cluster issuers.
- Secrets: `couchbase-cluster-auth` from Vault path `gitops/data/couchbase/admin`; referenced by CAO cluster and every nostr workload needing data plane access.
- Diff noise: status-only ignore in `charts/bitiq-umbrella/templates/app-couchbase-cluster.yaml` (spec drift remains visible).

### NostR application stack

Umbrella toggles: `nostrQueryEnabled`, `nostrThreadsEnabled`, `nostrThreadCopierEnabled`, `nostouchEnabled`, `nostrSiteEnabled`.

#### nostr-query (`charts/nostr-query/`)

- Stateless Deployment + Service (port 8081). No Route yet; traffic originates from other workloads.
- Env:
  - `env.envPrefix` and `gitCommitHash` set per env (local uses `dev` + Git SHA).
  - `ollamaHost` points at the Ollama endpoint (`https://ollama.cyphai.com` today).
- Secrets: `couchbase-cluster-auth` (username/password) and `nostr-query-credentials` (OPENAI API key). Both are VSO-managed in `bitiq-<env>`.
- NetworkPolicy: default deny with DNS + namespace egress.

#### nostr-threads (`charts/nostr-threads/`)

- API Deployment + Service (8081). Depends solely on Couchbase.
- Secrets: `couchbase-cluster-auth`. OpenAI is not required for this workload.
- Image tags tracked via Image Updater; env prefix/Git SHA values recorded per env.

#### nostr-thread-copier (`charts/nostr-thread-copier/`)

- Low-resource sidecar that copies Couchbase data between buckets. No external ingress.
- Configurable command/args; default container listens on port 80 → 8081 for readiness probes.
- Secrets: no direct Vault secret today; extend chart if credentials become necessary.

#### nostouch (`charts/nostouch/`)

- Streaming service that tails strfry via websocket and writes into Couchbase.
- Chart exposes `stream.*` block for replica count, relay URL (`ws://strfry.bitiq-local.svc.cluster.local:7777` on local), Couchbase connection string, and env metadata (prefix/git SHA).
- Ports: metrics (8080) + relay (7777). Probes hit `/healthz` `/readyz`.
- Secrets: `couchbase-cluster-auth` projected with env names `COUCHBASE_USER` / `COUCHBASE_PASSWORD`.
- NetworkPolicy: default deny with explicit allowances for DNS and namespace-local traffic.

#### nostr-site (`charts/nostr-site/`)

- Minimal nginx Deployment/Service with a Route (default) and an optional Ingress. The Route path uses the Route 53 DNS-01 issuer (`letsencrypt-dns01-route53-cyphai`) so it does not depend on WAN port 80 being reachable.
- When you want to experiment with HTTP-01, set `route.enabled=false` and `ingress.enabled=true` so cert-manager requests `letsencrypt-http01-local` against the Ingress. That path requires the router’s port 80 to be publicly reachable (see MIGRATION_PLAN next steps).
- Customize content by building a new container or layering ConfigMaps; no Secrets involved yet.

### Static web properties (nginx pack)

- Still sourced from `pac-config/services/nginx/` but reconciled via the umbrella Application `nginx-sites-<env>`.
- Contents:
  - Deployment (`1-nginx.yaml`), PVC (`7-static-site-pvc.yaml`), Service, and one-shot Job `init-static-sites` for seeding HTML bundles.
  - Ingress resources for `cyphai.com`, `didgo.com`, `paulcapestany.com`, `bitiq.io`, `noelcapestany.com`, `beatricecapestany.com`, `ipiqi.com`, `neuance.net`, `signet.ing`.
  - ConfigMaps for curated content (cyphai, neuance, signet) that gets copied into the PVC.
- Vault is not required; TLS relies on cert-manager issuers annotated on each Ingress (`letsencrypt-http01-local` by default).
- To refresh site assets, delete/recreate the seeding Job or bump its name; the PVC preserves user-provided content.

### Ollama + GPU prerequisites

- Chart: `charts/ollama/` with `mode` controlling behavior.
  - `external` (local default, `values-local.yaml`): creates a ConfigMap and optional `ExternalName` Service pointing to `https://ollama.cyphai.com:11434`. No cluster resources beyond metadata.
  - `gpu`: deploys an in-cluster Ollama pod with PVC (`100Gi` default), Service/Route, probes, and NetworkPolicy.
- GPU mode requirements:
  - Enable Node Feature Discovery + GPU Operator via `bootstrapOperators`.
  - Provide GPU-capable worker nodes or a Machineset (see MIGRATION_PLAN "Ollama" milestone for future automation).
  - Set `ollama.mode=gpu` and configure `gpu.nodeSelector`, `gpu.runtimeClassName`, `gpu.resources.requests["nvidia.com/gpu"]=1`.
  - Consider storage class overrides (`gpu.persistence.storageClassName`) for NVMe-backed RWX volumes if sharing models.
- Secrets: none by default, but you can project credentials by populating `gpu.env` / `gpu.envFrom` and sourcing from Vault-managed Secrets.

## Cert-backed endpoints (local)

| Host | Owner | Source |
| --- | --- | --- |
| `relay.cyphai.com` | Strfry Route | `charts/strfry/values-local.yaml` |
| `cb.cyphai.com` | Couchbase admin ingress/Route | `charts/couchbase-cluster/values-local.yaml` |
| `alpha.cyphai.com` | nostr-site Route | `charts/nostr-site/values-local.yaml` |
| `ollama.cyphai.com` | External Ollama endpoint (outside cluster) | `charts/ollama/values-local.yaml` |
| `www.cyphai.com`, `*.didgo.com`, `*.paulcapestany.com`, `*.bitiq.io`, `*.noelcapestany.com`, `*.beatricecapestany.com`, `*.ipiqi.com`, `*.neuance.net`, `*.signet.ing` | Static sites served by `pac-config/services/nginx` | `charts/bitiq-umbrella/templates/app-nginx-sites.yaml` |

Keep the DNS → WAN IP mapping in sync with your DDNS host and ensure HTTP-01 reachability (router 80/443) or stick with DNS-01.

## Next review targets

- Verify cert issuance end-to-end once router ports 80/443 are exposed publicly (MIGRATION_PLAN §M7).
- Populate any missing Vault paths (gpu secrets, nostr Thread Copier credentials) before enabling divergent envs.
- Track GPU operator enablement for future SNO/prod rollouts – update this document when GPU nodes exist.
