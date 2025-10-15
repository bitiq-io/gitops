# gitops

Helm-first GitOps repo for running the same Argo CD + Tekton CI/CD stack across:
- **OpenShift Local** (`ENV=local`)
- **Single-Node OpenShift (SNO)** (`ENV=sno`)
- **Full/Prod OCP** (`ENV=prod`)

It uses:
- Red Hat **OpenShift GitOps** (Argo CD) and **OpenShift Pipelines** (Tekton) installed via OLM Subscriptions.
- **ApplicationSet** + Helm `ignoreMissingValueFiles` to switch environments by changing a single `ENV`.  
- **Argo CD Image Updater** for auto image bumping (with write-back to Git Helm values).
- A **sample Helm app** to prove end-to-end CI→CD.

## Project docs

- [SPEC](SPEC.md)
- [TODO](TODO.md)
- [CONVENTIONS](docs/CONVENTIONS.md) — versioning, naming, and rollback guardrails
- [ROLLBACK](docs/ROLLBACK.md) — Git revert + Argo sync operational playbook
- [Architecture Decision Records](docs/adr/)
- [LOCAL-RUNBOOK](docs/LOCAL-RUNBOOK.md) — CRC quick runbook for ENV=local (macOS)
- [LOCAL-RUNBOOK-UBUNTU](docs/LOCAL-RUNBOOK-UBUNTU.md) — Remote Ubuntu/CRC runbook for ENV=local
- [LOCAL-CI-CD](docs/LOCAL-CI-CD.md) — End-to-end local CI→CD (webhook via dynamic DNS or tunnel)
- [SNO-RUNBOOK](docs/SNO-RUNBOOK.md) — Provision SNO and bootstrap ENV=sno
- [PROD-RUNBOOK](docs/PROD-RUNBOOK.md) — Bootstrap and operate ENV=prod on OCP 4.19
- [PROD-SECRETS](docs/PROD-SECRETS.md) — Manage prod secrets with Vault via VSO/VCO (ESO legacy flow noted)
- [OPERATOR-VERSIONS](docs/OPERATOR-VERSIONS.md) — pinned operator channels/CSVs and documentation links

## Prereqs

- OpenShift 4.x cluster (OpenShift Local, SNO, or full) and `oc`, `helm` in PATH
- Cluster-admin for bootstrap (OLM subscriptions, operators)
- Operator catalog access to install **OpenShift GitOps 1.18** (`channel: gitops-1.18`) and **OpenShift Pipelines 1.20** (`channel: pipelines-1.20`). See the [Operator Version Matrix](docs/OPERATOR-VERSIONS.md) for the exact CSVs and documentation targets (GitOps 1.18 / Pipelines 1.20).
- Git repo hosting (HTTPS or SSH) with ArgoCD repo credentials configured
- For OpenShift Local: the app base domain is `apps-crc.testing`. :contentReference[oaicite:7]{index=7}

OpenShift Local (CRC) resources

- For a smoother local experience, size CRC generously:
  - `crc config set memory 16384`
  - `crc config set cpus 6`
  - `crc config set disk-size 120`
- Note: resource changes take effect after `crc stop && crc delete && crc start`.

## Quick start

For detailed macOS/OpenShift Local setup, see `docs/LOCAL-SETUP.md`.

First-time local (CRC)? Use the interactive helper to bootstrap and seed credentials:

`make local-e2e`

```bash
# 1) Log in as cluster-admin
oc login https://api.<cluster-domain>:6443 -u <admin>

# 2) Clone this repo and cd in
git clone <your fork> gitops && cd gitops

# 3) Choose environment: local | sno | prod
export ENV=local

# Optional for sno/prod (base domain for Routes):
export BASE_DOMAIN=apps.sno.example    # e.g., apps.<yourcluster-domain>

# 4) Bootstrap operators and GitOps apps
./scripts/bootstrap.sh
```

Quick interactive setup (local):

```bash
# Guided helper that bootstraps, configures RBAC, and prompts for creds
make local-e2e
```

Headless fast path (non-interactive, remote server):

```bash
# Bootstrap + RBAC (secrets via Vault operators; no 'oc create secret')
FAST_PATH=true \
ENV=local BASE_DOMAIN=apps-crc.testing \
# Per-repo credentials (write access for this repo)
ARGOCD_REPO_URL='https://github.com/bitiq-io/gitops.git' \
ARGOCD_REPO_USERNAME='git' \
ARGOCD_REPO_PASSWORD='<github-pat>' \
./scripts/local-e2e-setup.sh

# Seed dev Vault with demo secrets (VSO will reconcile)
make dev-vault
```

Notes:
- Secrets are managed via Vault using VSO (runtime) and VCO (config). Rotate by writing to Vault (paths under `gitops/data/...`) and rerun `make dev-vault`.

After bootstrap finishes, run `./scripts/preflight.sh` to confirm the cluster meets the pinned GitOps 1.18 / Pipelines 1.20 baseline before syncing applications.

Local notes (OpenShift Local / CRC)

- Ensure CRC is fully ready before bootstrapping (run: crc setup && crc start).
- Get kubeadmin credentials with: crc console --credentials
- Login to the cluster: oc login -u kubeadmin -p <PASSWORD> https://api.crc.testing:6443


Single-Node OpenShift (SNO) quick path

Important: SNO requires an already-provisioned OpenShift cluster (Assisted/Agent-based install) and out‑of‑band ignition/discovery ISO assets. This repo does not generate ignition or perform cluster installs. As such, SNO is not a quick “try it locally” path and cannot be sanity‑checked without a real SNO cluster. For quick iteration and validation, prefer `ENV=local`.

- Follow the detailed checklist in [`docs/SNO-RUNBOOK.md`](docs/SNO-RUNBOOK.md) to provision the cluster, configure storage/DNS, and prepare secrets.
- Validate cluster readiness before bootstrapping:
  ```bash
  export BASE_DOMAIN=apps.<cluster-domain>
  ./scripts/sno-preflight.sh
  ```
- Bootstrap GitOps:
  ```bash
  export ENV=sno
  ENV=sno BASE_DOMAIN="$BASE_DOMAIN" ./scripts/bootstrap.sh
  ```
- If Argo CD manages the SNO cluster from within the cluster, no extra change is needed (`clusterServer=https://kubernetes.default.svc`). For a central Argo CD instance, keep the sno `clusterServer` pointed at the external API URL and register the cluster with `argocd cluster add` before syncing.
- After secrets are in place (`make image-updater-secret`, optional GitHub/quay secrets), run `make smoke ENV=sno BASE_DOMAIN="$BASE_DOMAIN"` to verify operator readiness, Argo CD sync, and sample Routes.


Production (ENV=prod) quick path

- See the full runbook in `docs/PROD-RUNBOOK.md` for prerequisites and operations hardening.
- Validate cluster readiness before bootstrapping:
  ```bash
  export BASE_DOMAIN=apps.<cluster-domain>
  ./scripts/prod-preflight.sh
  ```
- Bootstrap GitOps:
  ```bash
  export ENV=prod
  ENV=prod BASE_DOMAIN="$BASE_DOMAIN" ./scripts/bootstrap.sh
  ```
- After secrets are in place (Vault via VSO/VCO per `docs/PROD-SECRETS.md`), you can run:
  ```bash
  ./scripts/prod-smoke.sh
  ```


**What happens:**

1. Installs/ensures **OpenShift GitOps** (channel `gitops-1.18`) and **OpenShift Pipelines** (channel `pipelines-1.20`) via OLM Subscriptions aligned with the official compatibility matrices. ([GitOps 1.18 release notes][gitops-1-18-compat], [Pipelines 1.20 release notes][pipelines-1-20-compat])
2. Waits for the default **Argo CD** instance in `openshift-gitops` (unless disabled). ([Red Hat Docs][3])
3. Installs an **ApplicationSet** that creates **one** `bitiq-umbrella-${ENV}` Argo Application for your ENV.
4. Installs **Vault operators** — HashiCorp Vault Secrets Operator (VSO) and Red Hat COP Vault Config Operator (VCO) — via OLM Subscriptions per the [Operator Version Matrix](docs/OPERATOR-VERSIONS.md).
5. For ENV=local, the umbrella enables VSO/VCO Applications and gates off the legacy ESO examples to avoid dual writers. For other envs, enable VSO/VCO per env in the ApplicationSet values when ready.
6. The umbrella app deploys:

  * **image-updater** in `openshift-gitops` (as a k8s workload). ([Argo CD Image Updater][7])
  * (Legacy) **eso-vault-examples** in `external-secrets-operator` (ClusterSecretStore + ExternalSecrets for platform/app creds). This is gated off when VSO is enabled for an env. Migration to VSO/VCO is in progress (see docs/OPERATOR-VERSIONS.md and improvement plan T6/T17).

### Secret reload behavior

- Default: mount Secrets as files (no `subPath`) and let your app re‑read on change, optionally with a `configmap-reload` sidecar to call a reload webhook.
- For apps that cannot reload: use VSO’s `spec.rolloutRestartTargets` on the VaultStaticSecret to trigger a precise rolling restart only when the Secret’s HMAC changes. Tune `refreshAfter` to a sensible interval.
  * **ci-pipelines** in `openshift-pipelines` (Tekton pipelines + shared GitHub webhook triggers; configurable unit-test step + Buildah image build). ([Red Hat Docs][4])
  * **toy-service** and **toy-web** Argo Applications in a `bitiq-${ENV}` namespace, each with its own Deployment, Service, Route, and Image Updater automation.

### Sample app ownership & placement

Application code for the demo services lives in their own repositories:

- [`PaulCapestany/toy-service`](https://github.com/PaulCapestany/toy-service)
- [`PaulCapestany/toy-web`](https://github.com/PaulCapestany/toy-web)

Those repos stay free of Kubernetes manifests on purpose. All runtime configuration is rendered from this GitOps repo:

- Helm charts and env overlays: `charts/toy-service/` and `charts/toy-web/`
- Tekton pipelines and triggers: `charts/ci-pipelines/values*.yaml` (watches the service repos via webhook + CEL repo filters)
- Argo CD Image Updater write-back: automatically commits image tag bumps to `charts/toy-service/values-<env>.yaml` and `charts/toy-web/values-<env>.yaml`

When a service change requires an updated deployment (e.g., new env var, different resource limits), open a pull request here alongside the code change so reviewers can keep the GitOps manifests in sync. Issues and PRs in the service repos should link back to the relevant chart or values file in this repository to document how the change rolls out.

### Image updates & Git write-back

The `toy-service-${ENV}` and `toy-web-${ENV}` Argo Applications are annotated for **Argo CD Image Updater** so each service tracks its image and writes updates to Git:

* `toy-service-${ENV}` renders alias `toy-service` and commits back to `/charts/toy-service/values-${ENV}.yaml` (`image.repository` and `image.tag`).
* `toy-web-${ENV}` renders alias `toy-web` and commits back to `/charts/toy-web/values-${ENV}.yaml`.

Both Applications set `write-back-method: git` with the tracked branch, interval, platform filter, and optional pull secret configured via the umbrella chart’s `imageUpdater.*` values. ([Argo CD Image Updater][8])

Local env note

* Both sample apps (backend and frontend) have Image Updater enabled by default. If your registry is private, set `imageUpdater.pullSecret` so the updater can list tags.
* Pause either service’s write-back by flipping `toyServiceImageUpdater.pause` / `toyWebImageUpdater.pause` (forwarded to `imageUpdater.toyService.pause` and `.toyWeb.pause`). The corresponding Application drops Image Updater annotations until you resume it.

Ensure ArgoCD has repo creds with **write access** (SSH key or token). Image Updater will commit to the repo branch Argo tracks. ([Argo CD Image Updater][10])

Platform and private registry notes:
- Platform filter: the umbrella chart exposes `imageUpdater.platforms` (default `linux/amd64`) used by annotations to filter manifest architectures during tag selection. All environments map to `linux/amd64` by default (configured in `charts/argocd-apps/values.yaml` under `envs[].platforms`). Override to `linux/arm64` if your cluster nodes are arm64 (for example, Apple Silicon CRC); when bootstrapping, you can set `PLATFORMS_OVERRIDE=linux/arm64 ENV=local ./scripts/bootstrap.sh` to apply it without editing values.
- Private Quay repos: set `imageUpdater.pullSecret` to a Secret visible to the Argo CD namespace to allow Image Updater to list tags for private repos (annotation `*.pull-secret` is rendered when set). The secret can be referenced as `name` (in `openshift-gitops`) or `namespace/name`.
  VSO manages a pull secret for the updater in `openshift-gitops` (default name `quay-creds`).
  Seed Vault at `gitops/data/registry/quay` (key `dockerconfigjson`) and set `imageUpdater.pullSecret: quay-creds` in the umbrella values.

Local bump helper (optional)

You can force an update by creating a new tag in Quay that points at the current `latest` (or another `SOURCE_TAG`). The helper prefers `skopeo`, then `podman`, then `docker`.

Examples:

```bash
# Create a new tag from latest (e.g., dev-20250101-120000)
NEW_TAG=dev-$(date +%Y%m%d-%H%M%S) make bump-image

# With explicit auth (recommended for private repos or if not logged in)
QUAY_USERNAME=<user or robot> QUAY_PASSWORD=<token> \
NEW_TAG=dev-$(date +%s) make bump-and-tail ENV=local
```

Defaults used by the helper:

- `QUAY_REGISTRY=quay.io`
- `QUAY_NAMESPACE=paulcapestany`
- `QUAY_REPOSITORY=toy-service`
- `SOURCE_TAG=latest`
- `NEW_TAG=dev-<timestamp>`

Token secret configuration for Image Updater (VSO)

- Image Updater reads its API token from a VSO‑managed Secret (`openshift-gitops/argocd-image-updater-secret`).
- Write the token to Vault at `gitops/data/argocd/image-updater` (key: `token`) and run `make dev-vault` (local) or follow [PROD-SECRETS](docs/PROD-SECRETS.md) for sno/prod.
 - Rotation: after Vault updates and VSO reconciles the Secret, restart the deployment to pick up the new env var:
   `oc -n openshift-gitops rollout restart deploy/argocd-image-updater`.

### Tekton triggers

The **ci-pipelines** chart includes GitHub webhook **Triggers** (EventListener, TriggerBinding, TriggerTemplate). Point your GitHub webhook to the exposed Route of the EventListener to kick off builds on push/PR. ([Red Hat][11], [Tekton][12])

Secret management note: the webhook Secret is VSO‑managed. Seed Vault (path `gitops/data/github/webhook`, key `token`) and let VSO reconcile the Kubernetes Secret. Avoid `triggers.createSecret=true` under this policy.

## Vault Operators (VSO/VCO)

- Runtime (VSO) manages Kubernetes Secrets from Vault. Control‑plane (VCO) manages Vault itself (auth mount/config, roles, and policies). Both are installed via OLM in `scripts/bootstrap.sh`.
- The umbrella renders two Apps when enabled for an env:
  - `vault-config-<env>` (VCO): configures Kubernetes auth and ACL policy in Vault
  - `vault-runtime-<env>` (VSO): creates `VaultConnection`, `VaultAuth`, and `VaultStaticSecret` in target namespaces

What `vault-config` (VCO) creates

- `AuthEngineMount` (type `kubernetes`) and `KubernetesAuthEngineConfig` at the configured mount (default `kubernetes`).
- `Policy` (ACL) for the app KV mount (default `gitops`), granting kv‑v2 permissions to:
  - `path "<kvMount>/data/*"` (data) and `path "<kvMount>/metadata/*"` (metadata) — default capabilities: `read`, `list`.
- `KubernetesAuthEngineRole` (default name `gitops-<env>` or configured) bound to the `default` SA in three namespaces: gitops, pipelines, and app. The CR is annotated with Argo sync options `Replace=true,Force=true` to avoid immutable field update failures in VCO.

What `vault-runtime` (VSO) creates

- Per‑namespace `VaultConnection` and `VaultAuth` (method `kubernetes`, mount `kubernetes`, role `gitops-<env>`).
- `VaultStaticSecret` objects for:
  - `openshift-gitops/argocd-image-updater-secret` (path `gitops/argocd/image-updater`)
  - `openshift-pipelines/quay-auth` (path `gitops/registry/quay`)
  - `openshift-pipelines/github-webhook-secret` (path `gitops/github/webhook`)
  - App configs under the app namespace.

Key values

- Enablement is gated per env in the umbrella values (`vault.runtime.enabled`, `vault.config.enabled`).
- VCO chart (`charts/vault-config`):
  - `vault.kvMountPath` (default `gitops`) — KV v2 mount for app secrets
  - `policyCapabilities` (default `[read, list]`) — ACL capabilities applied to data/metadata paths
  - `vault.connectionRole`/`vault.serviceAccountName` — used for VCO’s own auth to Vault
- VSO chart (`charts/vault-runtime`):
  - `vault.address`, `vault.kubernetesMount`, `vault.roleName` — used for runtime auth
  - `namespaces.gitops|pipelines|app` — where to create runtime resources

Local dev (ENV=local)

- `make dev-vault` deploys a dev Vault and seeds demo secrets under `gitops/...`.
- The helper configures a permissive `kube-auth` policy so VCO can manage `/sys/policies/acl/*` locally and enables a kv‑v2 mount at `gitops/`.
- Use `VAULT_OPERATORS=true make dev-vault` to deploy the VSO runtime chart against the dev Vault.

Verification (handy commands)

- `oc -n openshift-gitops get application vault-config-<env> -o jsonpath='{.status.sync.status} {.status.health.status}\n'`
- `oc -n openshift-gitops get kubernetesauthenginerole gitops-<env> -o jsonpath='{.spec.targetNamespaces.targetNamespaces}\n'`
- `for ns in openshift-gitops openshift-pipelines <app-ns>; do oc -n $ns get vaultauth k8s -o jsonpath='{.spec.kubernetes.role}{"\n"}'; done`
- `for ns in openshift-gitops openshift-pipelines <app-ns>; do oc -n $ns get vaultstaticsecret -o name; done`

### Notes

* **OpenShift Local** app domain: `apps-crc.testing`. The chart defaults handle this when `ENV=local`. ([crc.dev][5])
* The **internal registry** is reachable inside the cluster at `image-registry.openshift-image-registry.svc:5000`. Use this for in‑cluster image references/pushes. ([Hewlett Packard][13], [Prisma Cloud Documentation][14])
* Applications use `syncOptions: CreateNamespace=true` so target namespaces are created automatically. ([Argo CD][6])

## Make targets

```bash
make lint       # helm lint all charts
make hu         # run helm-unittest suites (helm plugin required)
make template   # helm template sanity for each env
make validate   # full validation: helm render, kubeconform, conftest, yamllint
make verify-release  # assert appVersion matches env image tags (multi-image safe)
make pin-images           # pin sample-app tags per service across envs
make dev-setup  # install local commit-msg hook for commitlint
make smoke-image-update  # show app annotations and tail image-updater logs (ENV=<env>)
make bump-image           # create a new tag in Quay (SOURCE_TAG->NEW_TAG)
make bump-and-tail        # bump in Quay then tail image-updater logs
make smoke ENV=local [BOOTSTRAP=true]  # cluster smoke checks (optional bootstrap)
```

CI uses the same entrypoint: the workflow runs `make validate` for parity with local checks.

### Pinning image tags (automation)

Use the helper to pin tags in values-<env>.yaml, recompute the umbrella composite, optionally freeze/unfreeze Image Updater (per service), and optionally commit/push + Argo sync:

```bash
# Pin both services across all envs and freeze updater
SVC_TAG=v0.3.20-commit.abc1234 \
WEB_TAG=v0.1.20-commit.def5678 \
FREEZE=true make pin-images

# Pin only prod backend (skip verify across all envs)
ENVS=prod SVC_TAG=v0.3.21-commit.9999999 NO_VERIFY=1 make pin-images

# Per-service selection
# Pin only backend (infer service from SVC_TAG)
ENVS=local SVC_TAG=v0.3.22-commit.abcdef0 make pin-images
# Freeze only backend
ENVS=local SERVICES=backend make freeze-updater
# Unfreeze only frontend
ENVS=local SERVICES=frontend make unfreeze-updater

# Fully non-interactive end-to-end (commit, push, sync)
ENVS=local \\
SVC_TAG=v0.3.22-commit.abcdef0 \\
WEB_TAG=v0.1.21-commit.1234567 \\
YES=1 AUTO_COMMIT=1 AUTO_PUSH=1 SYNC=1 make pin-images

# Freeze/unfreeze only
ENVS=local make freeze-updater
ENVS=local make unfreeze-updater
```

Notes:
- Tag grammar is enforced: `vX.Y.Z-commit.<sha>`.
- By default all envs are updated; when envs differ, the helper skips `verify-release` and computes `appVersion` from the first selected env.
- Edits `charts/toy-service/values-<env>.yaml` and/or `charts/toy-web/values-<env>.yaml` based on chosen services, then runs `scripts/compute-appversion.sh`.
- Limit scope with `SERVICES=backend|frontend` (or `--services`); unfreezing resumes Image Updater so it writes the newest allowed tags back to Git automatically for the selected services.
- With `AUTO_COMMIT=1`, commits are created (freeze commit is separate by default). Use `SPLIT_COMMITS=false` to squash into one.
- With `AUTO_PUSH=1`, pushes to the current branch’s remote (default `origin`). Override with `REMOTE`/`BRANCH`.
- With `SYNC=1`, runs `argocd app sync bitiq-umbrella-<env>` and waits for health.

## Project docs

- [SPEC.md](SPEC.md) — scope, requirements, and acceptance criteria
- [TODO.md](TODO.md) — upcoming tasks in Conventional Commits format
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md) — canonical versioning & naming rules
- [docs/ROLLBACK.md](docs/ROLLBACK.md) — revert + resync runbook
- [AGENTS.md](AGENTS.md) — assistant-safe workflows and conventions
  - See also: `docs/adr/0002-helm-first-gitops-structure.md` for the Helm-first decision

## Contributing & Agents

- See `AGENTS.md` for assistant-safe workflows, commit/PR conventions, role templates under `agents/`, and validation steps.
- Refer to ecosystem templates and standards: https://github.com/PaulCapestany/ecosystem

## Troubleshooting

* If you prefer to **disable** the default ArgoCD instance and create a custom one, set `.operators.gitops.disableDefaultInstance=true` in `charts/bootstrap-operators/values.yaml`. ([Red Hat Docs][3])
* Helm `valueFiles` not found? We intentionally use `ignoreMissingValueFiles: true` in Argo’s Helm source. ([Argo CD][1])
* Image Updater RBAC: the `argocd-image-updater` ServiceAccount must be able to `get,list,watch` `secrets` and `configmaps` in the Argo CD namespace (`openshift-gitops`). The chart defines a namespaced `Role` + `RoleBinding` for this. If you see errors like “secrets is forbidden … cannot list … in the namespace openshift-gitops”, re‑sync the `image-updater` app to apply RBAC.
* GitHub PAT shows “Never used”: ensure you log into Argo CD with `argocd login ... --sso --grpc-web` before running `argocd repo add`. Sanity-check the token with `curl -H "Authorization: Bearer $GH_PAT" https://api.github.com/repos/bitiq-io/gitops` and `git ls-remote https://<user>:$GH_PAT@github.com/bitiq-io/gitops.git`. Either call should flip the PAT to “Last used …” in GitHub’s UI.

## Operations

- Rollbacks: follow [`docs/ROLLBACK.md`](docs/ROLLBACK.md) for Git revert + Argo sync recovery. The playbook assumes the deterministic tag and `appVersion` conventions in [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md).
- App naming: Argo Applications carry the env suffix (`bitiq-umbrella-${ENV}`, `ci-pipelines-${ENV}`, `image-updater-${ENV}`, `toy-service-${ENV}`, `toy-web-${ENV}`) and are labeled `bitiq.io/env=${ENV}`. Namespaces inherit the same label for fleet queries.
- CI: GitHub Actions (`.github/workflows/validate.yaml`) runs `make hu`, `make template`, `make validate`, and `make verify-release` on every PR/push to catch Helm/template regressions before they reach the cluster.

## How to use it

1. **Bootstrap** (one env at a time on the current cluster):

```bash
export ENV=local            # or sno|prod
export BASE_DOMAIN=apps-crc.testing   # local default; required for sno/prod
./scripts/bootstrap.sh
```

2. **Configure Argo CD repo creds** with write access to this Git repo (for Image Updater’s Git write-back). Image Updater uses Argo CD’s API + repo credentials. ([Argo CD Image Updater][10])

   Common OpenShift GitOps CLI flow (SSO + PAT):

   ```bash
   export ARGOCD_SERVER=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')
   argocd login "$ARGOCD_SERVER" --sso --grpc-web

   # Fine-grained PAT with Contents:Read/Write (authorize for the org via "Configure SSO")
   export GH_PAT=<your_token>
   argocd repo add https://github.com/bitiq-io/gitops.git \
     --username <github-username> \
     --password "$GH_PAT" --grpc-web
   ```

   Sanity checks (PAT should show as “Last used” in GitHub after either call succeeds):

   ```bash
   curl -sS https://api.github.com/repos/bitiq-io/gitops \
     -H "Authorization: Bearer $GH_PAT" \
     -H "X-GitHub-Api-Version: 2022-11-28" | head -n 5

   git ls-remote https://<github-username>:$GH_PAT@github.com/bitiq-io/gitops.git | head
   ```

   If using SSH or a GitHub App, configure the matching repo credential instead. Always authorize PATs/SSH keys for the org (GitHub → Settings → Organizations → bitiq-io → Configure SSO).

3. **(Optional) GitHub webhook**
   Grab the Route URL named `bitiq-listener` in `openshift-pipelines` (it targets service `el-bitiq-listener`) and add it as a GitHub webhook for your microservice repo (content type: JSON; secret = the value you set in `triggers.githubSecretName`). ([Red Hat][11], [Tekton][15])

4. **Access the app**
   The sample Route host is `svc-api.${BASE_DOMAIN}`. For OpenShift Local that’s `svc-api.apps-crc.testing`. ([crc.dev][5])

---

## Why these choices (evidence-backed)

* **Operator channels**: pin to GitOps `gitops-1.18` and Pipelines `pipelines-1.20` to stay inside supported compatibility ranges. ([GitOps 1.18 release notes][gitops-1-18-compat], [Pipelines 1.20 release notes][pipelines-1-20-compat])
* **Image Updater** as a workload in Argo’s namespace and configured via an **API token** secret is the recommended “method 1” install. ([Argo CD Image Updater][7])
* **Helm `ignoreMissingValueFiles`** is supported declaratively by Argo and is ideal for env overlay selection with a single template. ([Argo CD][1])
* **Buildah task + `pipeline` SA** are installed by OpenShift Pipelines; this Pipeline expects those defaults. ([Red Hat Docs][4])
* **OpenShift Local** uses `apps-crc.testing` for app routes. ([crc.dev][5])
* **CreateNamespace sync option** lets Argo create the target namespace when syncing child apps. ([Argo CD][6])

---

## What you’ll likely adjust

* **Image repos** (`sampleAppImages.backend` and `.frontend`) to real images you build with Tekton.
* **GitHub webhook secret** in `ci-pipelines` values.
* **BASE\_DOMAIN** for SNO/prod (often `apps.<cluster-domain>`).

---

TODO: add a second example microservice and wire **App-of-Apps dependencies** (e.g., DB first, then API) using Argo CD sync phases — or convert the image bump from Image Updater to a **Tekton PR** flow that edits the env Helm values directly (both patterns are compatible with this layout)

[1]: https://argo-cd.readthedocs.io/en/latest/user-guide/helm/?utm_source=chatgpt.com "Helm - Argo CD - Declarative GitOps CD for Kubernetes"
[2]: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/installing_openshift_gitops/index?utm_source=chatgpt.com "Installing Red Hat OpenShift GitOps 1.18"
[3]: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/argo_cd_instance/setting-up-argocd-instance?utm_source=chatgpt.com "Chapter 1. Setting up an Argo CD instance"
[4]: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20/html/installing_red_hat_openshift_pipelines/index?utm_source=chatgpt.com "Installing Red Hat OpenShift Pipelines 1.20"
[5]: https://crc.dev/docs/networking/?utm_source=chatgpt.com "Networking :: CRC Documentation"
[6]: https://argo-cd.readthedocs.io/en/latest/user-guide/sync-options/?utm_source=chatgpt.com "Sync Options - Argo CD - Declarative GitOps CD for Kubernetes"
[7]: https://argocd-image-updater.readthedocs.io/en/stable/install/installation/?utm_source=chatgpt.com "Installation - Argo CD Image Updater"
[8]: https://argocd-image-updater.readthedocs.io/en/latest/basics/update-methods/?utm_source=chatgpt.com "Update methods - Argo CD Image Updater"
[9]: https://argocd-image-updater.readthedocs.io/en/release-0.13/configuration/images/?utm_source=chatgpt.com "Argo CD Image Updater - Read the Docs"
[10]: https://argocd-image-updater.readthedocs.io/en/stable/basics/update-methods/?utm_source=chatgpt.com "Update methods - Argo CD Image Updater"
[11]: https://www.redhat.com/en/blog/guide-to-openshift-pipelines-part-6-triggering-pipeline-execution-from-github?utm_source=chatgpt.com "Guide to OpenShift Pipelines Part 6 - Triggering Pipeline Execution ..."
[12]: https://tekton.dev/docs/triggers/?utm_source=chatgpt.com "Triggers and EventListeners - Tekton"
[13]: https://hewlettpackard.github.io/OpenShift-on-SimpliVity/post-deploy/expose-registry?utm_source=chatgpt.com "Exposing the image registry | Red Hat OpenShift Container ..."
[14]: https://docs.prismacloud.io/en/compute-edition/32/admin-guide/vulnerability-management/registry-scanning/scan-openshift?utm_source=chatgpt.com "Scan images in OpenShift integrated Docker registry"
[15]: https://tekton.dev/docs/triggers/eventlisteners/?utm_source=chatgpt.com "EventListeners - Tekton"

## License & Maintainers

This project is licensed under the [ISC License](LICENSE).
See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## Security

For vulnerability reporting, please see [SECURITY.md](SECURITY.md).

[gitops-1-18-compat]: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/release_notes/gitops-release-notes#GitOps-compatibility-support-matrix_gitops-release-notes "Red Hat OpenShift GitOps 1.18 compatibility matrix"
[pipelines-1-20-compat]: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20/html/release_notes/op-release-notes-1-20#compatibility-support-matrix_op-release-notes "Red Hat OpenShift Pipelines 1.20 compatibility matrix"
