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
- [Architecture Decision Records](docs/adr/)
- [LOCAL-RUNBOOK](docs/LOCAL-RUNBOOK.md) — CRC quick runbook for ENV=local

## Prereqs

- OpenShift 4.x cluster (OpenShift Local, SNO, or full) and `oc`, `helm` in PATH
- Cluster-admin for bootstrap (OLM subscriptions, operators)
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

Local notes (OpenShift Local / CRC)

- Ensure CRC is fully ready before bootstrapping (run: crc setup && crc start).
- Get kubeadmin credentials with: crc console --credentials
- Login to the cluster: oc login -u kubeadmin -p <PASSWORD> https://api.crc.testing:6443


**What happens:**

1. Installs/ensures **OpenShift GitOps** and **OpenShift Pipelines** via OLM Subscriptions.
   Use channels `latest` or versioned `gitops-<ver>` / `pipelines-<ver>` as needed. ([Red Hat Docs][2])
2. Waits for the default **Argo CD** instance in `openshift-gitops` (unless disabled). ([Red Hat Docs][3])
3. Installs an **ApplicationSet** that creates **one** `bitiq-umbrella-${ENV}` Argo Application for your ENV.
4. The umbrella app deploys:

   * **image-updater** in `openshift-gitops` (as a k8s workload). ([Argo CD Image Updater][7])
   * **ci-pipelines** in `openshift-pipelines` (pipeline + triggers; Buildah & SA come from the operator). ([Red Hat Docs][4])
   * **bitiq-sample-app** in a `bitiq-${ENV}` namespace with an OpenShift Route on your base domain.

### Image updates & Git write-back

The `bitiq-sample-app` Argo Application is annotated for **Argo CD Image Updater** to track an image and write back **Helm values** in Git:

* We use `argocd-image-updater.argoproj.io/write-back-method: git` and
  `argocd-image-updater.argoproj.io/write-back-target: helmvalues:charts/bitiq-sample-app/values-${ENV}.yaml`. ([Argo CD Image Updater][8])
* We also map Helm parameters via `*.helm.image-name` and `*.helm.image-tag`. ([Argo CD Image Updater][9])

Ensure ArgoCD has repo creds with **write access** (SSH key or token). Image Updater will commit to the repo branch Argo tracks. ([Argo CD Image Updater][10])

Token secret configuration for Image Updater

- The chart supports providing the Argo CD API token via an existing Secret (recommended) or creating one from values.
- Values (charts/image-updater/values.yaml):
  - `secret.create`: set to `true` to create the Secret from `.argocd.token`; default `false`.
  - `secret.name`: Secret name to reference (default `argocd-image-updater-secret`).
  - `secret.key`: Secret key containing the token (default `argocd.token`).
  - If `secret.create=true`, set `argocd.token` to the token value (or pass via `--set`).
  - For production, prefer SealedSecrets/External Secrets and set `secret.create=false` with `secret.name` pointing to the managed Secret.

CLI helper for local e2e:

```bash
# After "argocd login ... --sso --grpc-web --insecure"
export ARGOCD_TOKEN=$(argocd account generate-token --grpc-web)
make image-updater-secret   # applies/updates secret and restarts updater
```

If your SSO user cannot generate a token (error: `account '<user>' does not exist`), define a dedicated local Argo CD account and generate a token for it:

```bash
oc -n openshift-gitops patch argocd openshift-gitops --type merge -p '{
  "spec":{
    "extraConfig":{"accounts.argocd-image-updater":"apiKey"},
    "rbac":{"policy":"g, kubeadmin, role:admin\n\ng, argocd-image-updater, role:admin\n\np, role:admin, *, *, *, allow\n","scopes":"[groups, sub, preferred_username, email]"}
  }
}'
oc -n openshift-gitops rollout restart deploy/openshift-gitops-server
argocd login "$ARGOCD_HOST" --sso --grpc-web --insecure
export ARGOCD_TOKEN=$(argocd account generate-token --grpc-web --account argocd-image-updater)
make image-updater-secret
```

### Tekton triggers

The **ci-pipelines** chart includes GitHub webhook **Triggers** (EventListener, TriggerBinding, TriggerTemplate). Point your GitHub webhook to the exposed Route of the EventListener to kick off builds on push/PR. ([Red Hat][11], [Tekton][12])

Secret management note: the chart does not create the webhook Secret by default to avoid overwriting manual/managed secrets. Manually create it or set `triggers.createSecret=true` and provide `triggers.secretToken`.

### Notes

* **OpenShift Local** app domain: `apps-crc.testing`. The chart defaults handle this when `ENV=local`. ([crc.dev][5])
* The **internal registry** is reachable inside the cluster at `image-registry.openshift-image-registry.svc:5000`. Use this for in‑cluster image references/pushes. ([Hewlett Packard][13], [Prisma Cloud Documentation][14])
* Applications use `syncOptions: CreateNamespace=true` so target namespaces are created automatically. ([Argo CD][6])

## Make targets

```bash
make lint       # helm lint all charts
make template   # helm template sanity for each env
make validate   # full validation: helm render, kubeconform, conftest, yamllint
make dev-setup  # install local commit-msg hook for commitlint
make smoke ENV=local [BOOTSTRAP=true]  # cluster smoke checks (optional bootstrap)
```

CI uses the same entrypoint: the workflow runs `make validate` for parity with local checks.

## Project docs

- [SPEC.md](SPEC.md) — scope, requirements, and acceptance criteria
- [TODO.md](TODO.md) — upcoming tasks in Conventional Commits format
- [AGENTS.md](AGENTS.md) — assistant-safe workflows and conventions
  - See also: `docs/adr/0002-helm-first-gitops-structure.md` for the Helm-first decision

## Contributing & Agents

- See `AGENTS.md` for assistant-safe workflows, commit/PR conventions, role templates under `agents/`, and validation steps.
- Refer to ecosystem templates and standards: https://github.com/PaulCapestany/ecosystem

## Troubleshooting

* If you prefer to **disable** the default ArgoCD instance and create a custom one, set `.operators.gitops.disableDefaultInstance=true` in `charts/bootstrap-operators/values.yaml`. ([Red Hat Docs][3])
* Helm `valueFiles` not found? We intentionally use `ignoreMissingValueFiles: true` in Argo’s Helm source. ([Argo CD][1])

## How to use it

1. **Bootstrap** (one env at a time on the current cluster):

```bash
export ENV=local            # or sno|prod
export BASE_DOMAIN=apps-crc.testing   # local default; required for sno/prod
./scripts/bootstrap.sh
```

2. **Configure Argo CD repo creds** with write access to this Git repo (for Image Updater’s Git write-back). See Argo CD docs for repo credentials; Image Updater uses Argo CD’s API & repo creds. ([Argo CD Image Updater][10])

3. **(Optional) GitHub webhook**
   Grab the Route URL named `bitiq-listener` in `openshift-pipelines` (it targets service `el-bitiq-listener`) and add it as a GitHub webhook for your microservice repo (content type: JSON; secret = the value you set in `triggers.githubSecretName`). ([Red Hat][11], [Tekton][15])

4. **Access the app**
   The sample Route host is `svc-api.${BASE_DOMAIN}`. For OpenShift Local that’s `svc-api.apps-crc.testing`. ([crc.dev][5])

---

## Why these choices (evidence-backed)

* **Operator channels**: use `latest` or versioned `gitops-<ver>` / `pipelines-<ver>`. These are the supported patterns in official docs. ([Red Hat Docs][2])
* **Image Updater** as a workload in Argo’s namespace and configured via an **API token** secret is the recommended “method 1” install. ([Argo CD Image Updater][7])
* **Helm `ignoreMissingValueFiles`** is supported declaratively by Argo and is ideal for env overlay selection with a single template. ([Argo CD][1])
* **Buildah task + `pipeline` SA** are installed by OpenShift Pipelines; this Pipeline expects those defaults. ([Red Hat Docs][4])
* **OpenShift Local** uses `apps-crc.testing` for app routes. ([crc.dev][5])
* **CreateNamespace sync option** lets Argo create the target namespace when syncing child apps. ([Argo CD][6])

---

## What you’ll likely adjust

* **Image repo** (`sampleAppImageRepo`) to a real image you build with Tekton.
* **GitHub webhook secret** in `ci-pipelines` values.
* **BASE\_DOMAIN** for SNO/prod (often `apps.<cluster-domain>`).

---

TODO: add a second example microservice and wire **App-of-Apps dependencies** (e.g., DB first, then API) using Argo CD sync phases — or convert the image bump from Image Updater to a **Tekton PR** flow that edits the env Helm values directly (both patterns are compatible with this layout)

[1]: https://argo-cd.readthedocs.io/en/latest/user-guide/helm/?utm_source=chatgpt.com "Helm - Argo CD - Declarative GitOps CD for Kubernetes"
[2]: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.13/html/installing_gitops/installing-openshift-gitops?utm_source=chatgpt.com "Chapter 2. Installing Red Hat OpenShift GitOps"
[3]: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.13/html/argo_cd_instance/setting-up-argocd-instance?utm_source=chatgpt.com "Chapter 1. Setting up an Argo CD instance"
[4]: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.14/html/about_openshift_pipelines/understanding-openshift-pipelines?utm_source=chatgpt.com "Chapter 3. Understanding OpenShift Pipelines"
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
