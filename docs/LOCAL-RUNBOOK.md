# Local Runbook (OpenShift Local / CRC)

> Migration note: Secrets are moving from ESO to Vault operators (VSO/VCO). VSO/VCO are installed by bootstrap (see docs/VERSION-MATRIX.md). Until cutover completes, you may still see ESO-managed resources; follow VSO/VCO guidance for new secrets.

This is a concise, copy/pasteable sequence to get ENV=local running end‑to‑end on OpenShift Local (CRC) for smoke testing.

## Quick Interactive Setup

Prefer a guided flow that bootstraps, configures RBAC, and prompts for required credentials/secrets:

```bash
make local-e2e
# or
ENV=local BASE_DOMAIN=apps-crc.testing ./scripts/local-e2e-setup.sh
```

Prereqs: you’re logged in as cluster‑admin (`oc login -u kubeadmin ...`) and have the `argocd` CLI installed and logged in to the OpenShift GitOps route (`--sso --grpc-web --insecure`). For details and follow‑ups (webhook exposure, CI trigger), see `docs/LOCAL-CI-CD.md`.

### Headless Fast Path (non-interactive)

On headless/remote environments you can skip prompts and `argocd` CLI login by providing credentials via env vars. The helper seeds secrets and repo credentials, refreshes Argo, and waits for apps to sync.

```bash
FAST_PATH=true \
ENV=local BASE_DOMAIN=apps-crc.testing \
GITHUB_WEBHOOK_SECRET='<random-webhook-secret>' \
QUAY_USERNAME='<quay-user>' QUAY_PASSWORD='<quay-token>' QUAY_EMAIL='<you@example.com>' \
ARGOCD_TOKEN='<argocd-api-token>' \
# Per-repo credentials (write access for this repo)
ARGOCD_REPO_URL='https://github.com/bitiq-io/gitops.git' \
ARGOCD_REPO_USERNAME='git' \
ARGOCD_REPO_PASSWORD='<github-pat>' \
# Optional host-wide credentials for all repos under a prefix (e.g., GitHub)
ARGOCD_REPOCREDS_URL='https://github.com' \
ARGOCD_REPOCREDS_USERNAME='git' \
ARGOCD_REPOCREDS_PASSWORD='<github-pat>' \
./scripts/local-e2e-setup.sh
```

Notes:
- Uses `SKIP_APP_WAIT=true` for bootstrap, then applies RBAC/secrets and triggers a hard refresh before waiting for Healthy/Synced.
- Accepts `GH_PAT` as an alias for `ARGOCD_REPO_PASSWORD`/`ARGOCD_REPOCREDS_PASSWORD`.

## 0) Size CRC and start

```bash
crc stop || true
crc delete -f || true
crc config set memory 16384
crc config set cpus 6
crc config set disk-size 120
crc setup && crc start

# Login
# Extract kubeadmin password reliably from CRC credentials output
oc login -u kubeadmin -p "$(crc console --credentials | awk -F': *' '/Password/ {print $2; exit}')" https://api.crc.testing:6443
```

## 1) Bootstrap GitOps apps (local)

```bash
git pull
export ENV=local BASE_DOMAIN=apps-crc.testing
./scripts/bootstrap.sh
```

This installs GitOps + Pipelines operators (OLM) and an ApplicationSet that generates one umbrella Application for `local`.

Notes for local storage usage (CRC):
- The bootstrap now disables Tekton Results by default on ENV=local using `TektonConfig.spec.result.disabled=true` to prevent the Results Postgres PVC from consuming ~all CRC disk. Override with `TEKTON_RESULTS=true` if you need Results locally.
  - Examples:
    - Keep Results: `TEKTON_RESULTS=true ./scripts/bootstrap.sh`
    - Default (Results disabled): `./scripts/bootstrap.sh`
  - If supported by your operator build, you can also shrink storage via `TEKTON_RESULTS_STORAGE=5Gi`.

## 2) Seed Vault secrets (ENV=local)

Run the helper target to deploy a dev Vault, configure Kubernetes auth, seed the required `gitops/data/...` paths, create the `vault-auth` ServiceAccount, and reconcile secrets via the installed Vault operators.

Tip: set `VAULT_OPERATORS=true` to force the VSO runtime path locally (uninstalls the legacy ESO chart if present and installs the `vault-runtime` chart pointing to the dev Vault).

```bash
make dev-vault
```

Re-run the target whenever you update local credentials or tweak chart values. To clean up the dev Vault and uninstall the chart:

```bash
make dev-vault-down
```

Verify that secrets reconcile in `openshift-gitops`, `openshift-pipelines`, and `bitiq-local` using the commands in [PROD-SECRETS](PROD-SECRETS.md). The umbrella gates off ESO when VSO is enabled for local.

Environment overrides for the dev Vault helper:

- `DEV_VAULT_IMAGE` → override the vault image (default `hashicorp/vault:1.15.6`).
- `DEV_VAULT_IMPORT` (default `true`) → attempt an OpenShift ImageStream import first (with a short timeout) to handle registry mirror rewrites on OCP. On timeout/failure, the helper falls back to the source image automatically. Set to `false` to skip import altogether.
- `DEV_VAULT_IMPORT_TIMEOUT=<seconds>` → cap the import attempt duration (default `15`); on timeout the helper falls back to the source image.

Troubleshooting: If you see “Deploying dev Vault in namespace vault-dev” with no progress, your cluster likely can’t import from Docker Hub. Use one of the overrides above (skip import, change image, or extend timeout) and re‑run `make dev-vault`.

## 3) Limit AppSet to local (already done by bootstrap)

Bootstrap passes `envFilter=local`. If you ever need to reapply the AppSet manually:

```bash
oc -n openshift-gitops apply -f <(helm template charts/argocd-apps --set envFilter=local)
```

## 4) ArgoCD RBAC and repository credentials

ArgoCD is operator‑managed on OpenShift. To persist RBAC changes, patch the ArgoCD CR (not the `argocd-rbac-cm` directly).

Grant admin to kubeadmin locally (dev convenience), and allow all admin actions:

```bash
oc -n openshift-gitops patch argocd openshift-gitops \
  --type merge -p '{"spec":{"rbac":{"policy":"g, kubeadmin, role:admin\np, role:admin, *, *, *, allow\n","scopes":"[groups, sub, preferred_username, email]"}}}'
oc -n openshift-gitops rollout restart deploy/openshift-gitops-server
```

Then connect the repo with write access (CLI or UI).

CLI (works well with OpenShift GitOps + SSO):

```bash
ARGOCD_HOST=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')
argocd login "$ARGOCD_HOST" --sso --grpc-web

# Fine-grained PAT with Contents:Read/Write. Authorize for the bitiq-io org via "Configure SSO".
export GH_PAT=<your_token>
argocd repo add https://github.com/bitiq-io/gitops.git \
  --username <github-username> \
  --password "$GH_PAT" --grpc-web
```

Sanity checks (PAT should switch from “Never used” after either call succeeds):

```bash
curl -sS https://api.github.com/repos/bitiq-io/gitops \
  -H "Authorization: Bearer $GH_PAT" \
  -H "X-GitHub-Api-Version: 2022-11-28" | head -n 5

git ls-remote https://<github-username>:$GH_PAT@github.com/bitiq-io/gitops.git | head
```

UI alternative (if you prefer the console):

```bash
open https://$ARGOCD_HOST   # or paste in browser
```

Argo UI → Settings → Repositories → Connect repo using HTTPS
- Repository URL: https://github.com/bitiq-io/gitops.git
- Username: any non-empty (e.g., your GitHub username)
- Password: the SSO-authorized PAT (or use SSH / GitHub App credentials)

Tip: the operator writes the effective RBAC into `argocd-rbac-cm`; verify with:

```bash
oc -n openshift-gitops get cm argocd-rbac-cm -o json | jq -r '.data["policy.csv"]'
```

## 5) Allow ArgoCD to manage the target namespace

```bash
oc new-project bitiq-local || true
oc -n bitiq-local create rolebinding argocd-app-admin \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller || true

# Also grant Argo CD controller admin in openshift-pipelines so it can create Tekton resources
oc -n openshift-pipelines create rolebinding argocd-app-admin \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller || true
```

## 6) (Optional) Rotate Image Updater token via Vault

Image Updater reads its token from Vault via the Vault Secrets Operator (VSO). If you need to rotate the token, generate a new value in Argo CD, write it to `gitops/data/argocd/image-updater` (using `vault kv put ... token="<new-token>"`), and rerun `make dev-vault` if using the local helper. Do not recreate the Kubernetes Secret manually.

## 7) Auto‑sync child apps

```bash
oc -n openshift-gitops patch application toy-service-${ENV} \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}'

oc -n openshift-gitops patch application toy-web-${ENV} \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}'

oc -n openshift-gitops patch application ci-pipelines-${ENV} \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

## 8) Smoke check

```bash
make smoke ENV=local

# Or directly:
oc -n openshift-gitops get applications
APP_HOST=$(oc -n bitiq-local get route toy-service -o jsonpath='{.spec.host}')
echo "https://$APP_HOST" && curl -k "https://$APP_HOST/healthz" || true
```

## 9) Sample app images (public by default)

- The sample stack ships with two images:
  - Backend (`toy-service`) — defaults to `quay.io/paulcapestany/toy-service` with probes on `/healthz`.
  - Frontend (`toy-web`) — defaults to `quay.io/paulcapestany/toy-web` with probes on `/`.
- These live in `charts/toy-service/values-*.yaml` and `charts/toy-web/values-*.yaml` (`image.repository`, `image.tag`, `healthPath`, `hostPrefix`, and `service.port`).
- If you swap to your own images, ensure ports/probes line up; then hard refresh:
  ```bash
  oc -n openshift-gitops annotate application toy-service-local argocd.argoproj.io/refresh=hard --overwrite
  oc -n openshift-gitops annotate application toy-web-local argocd.argoproj.io/refresh=hard --overwrite
  ```

## Quick Troubleshooting

- DiskPressure on CRC: increase CRC resources (above), or prune images/logs on the node:
  ```bash
  oc debug node/crc -- chroot /host crictl rmi --prune || true
  oc debug node/crc -- chroot /host journalctl --vacuum-time=2d || true
  oc adm taint nodes crc node.kubernetes.io/disk-pressure:NoSchedule- || true
  ```
- If the umbrella app is Healthy but children are Missing, ensure the rolebinding in `bitiq-local` exists (step 3), then hard refresh:
  ```bash
  oc -n openshift-gitops annotate application toy-service-local argocd.argoproj.io/refresh=hard --overwrite
  oc -n openshift-gitops annotate application toy-web-local argocd.argoproj.io/refresh=hard --overwrite
  ```
