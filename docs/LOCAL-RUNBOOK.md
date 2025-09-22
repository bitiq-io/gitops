# Local Runbook (OpenShift Local / CRC)

This is a concise, copy/pasteable sequence to get ENV=local running end‑to‑end on OpenShift Local (CRC) for smoke testing.

## 0) Size CRC and start

```bash
crc stop || true
crc delete -f || true
crc config set memory 16384
crc config set cpus 6
crc config set disk-size 120
crc setup && crc start

# Login
oc login -u kubeadmin -p $(crc console --credentials | awk '/kubeadmin/ {print $2}') https://api.crc.testing:6443
```

## 1) Bootstrap GitOps apps (local)

```bash
git pull
export ENV=local BASE_DOMAIN=apps-crc.testing
./scripts/bootstrap.sh
```

This installs GitOps + Pipelines operators (OLM) and an ApplicationSet that generates one umbrella Application for `local`.

## 2) Limit AppSet to local (already done by bootstrap)

Bootstrap passes `envFilter=local`. If you ever need to reapply the AppSet manually:

```bash
oc -n openshift-gitops apply -f <(helm template charts/argocd-apps --set envFilter=local)
```

## 3) ArgoCD RBAC and repository credentials

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

## 3) Allow ArgoCD to manage the target namespace

```bash
oc new-project bitiq-local || true
oc -n bitiq-local create rolebinding argocd-app-admin \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller || true
```

## 4) Seed Image Updater token (dev)

```bash
oc -n openshift-gitops create secret generic argocd-image-updater-secret \
  --from-literal=argocd.token=dummy || true
oc -n openshift-gitops rollout restart deploy/argocd-image-updater
```

Notes:
- Dummy token lets the pod run for smoke tests. For a real token, log into ArgoCD via SSO and create a token, then update the Secret.
- The chart supports `secret.create=false` (default) to use an existing Secret, or `secret.create=true` to create from values.

Preferred: create a dedicated Argo CD local account for Image Updater and generate a token for it (works reliably with SSO):

```bash
# 4a) Define a local Argo CD account for the updater and RBAC (operator-managed)
oc -n openshift-gitops patch argocd openshift-gitops \
  --type merge -p '{
    "spec":{
      "extraConfig":{
        "accounts.argocd-image-updater":"apiKey"
      },
      "rbac":{
        "policy":"g, kubeadmin, role:admin\n"
                 "g, argocd-image-updater, role:admin\n"
                 "p, role:admin, *, *, *, allow\n",
        "scopes":"[groups, sub, preferred_username, email]"
      }
    }
  }'

# 4b) Restart the Argo CD server to pick up RBAC/extraConfig changes
oc -n openshift-gitops rollout restart deploy/openshift-gitops-server

# 4c) Login via SSO and generate a token for the local account
ARGOCD_HOST=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')
argocd login "$ARGOCD_HOST" --sso --grpc-web --insecure
export ARGOCD_TOKEN=$(argocd account generate-token --grpc-web --account argocd-image-updater)
make image-updater-secret
```

If you see `account '<user>' does not exist` when generating a token for your SSO user:

1) Ensure you log in to Argo CD first via SSO and verify your identity:

```bash
ARGOCD_HOST=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')
argocd login "$ARGOCD_HOST" --sso --grpc-web --insecure
argocd account get-user-info --grpc-web   # should print your SSO username (e.g., kubeadmin)
```

2) Ensure RBAC grants your user admin rights (dev convenience):

```bash
oc -n openshift-gitops patch argocd openshift-gitops \
  --type merge -p '{"spec":{"rbac":{"policy":"g, kubeadmin, role:admin\np, role:admin, *, *, *, allow\n","scopes":"[groups, sub, preferred_username, email]"}}}'
oc -n openshift-gitops rollout restart deploy/openshift-gitops-server
```

3) Re-login and generate the token for your user (or prefer the dedicated account method above):

```bash
argocd login "$ARGOCD_HOST" --sso --grpc-web --insecure
export ARGOCD_TOKEN=$(argocd account generate-token --grpc-web)
make image-updater-secret   # uses $ARGOCD_TOKEN to (re)create the secret and restart the deployment
```

If your environment still refuses SSO token generation for users, create a dedicated local account with API key via the Argo CD config (operator‑managed) as a follow‑up; otherwise, prefer SSO tokens.

Real token flow (optional, for write‑back):

```bash
ARGOCD_HOST=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')
argocd login "$ARGOCD_HOST" --sso --grpc-web --insecure
TOKEN=$(argocd account generate-token --grpc-web)
oc -n openshift-gitops create secret generic argocd-image-updater-secret \
  --from-literal=argocd.token="$TOKEN" --dry-run=client -o yaml | oc apply -f -
oc -n openshift-gitops rollout restart deploy/argocd-image-updater
```

## 5) Auto‑sync child apps

```bash
oc -n openshift-gitops patch application bitiq-sample-app-local \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}'

oc -n openshift-gitops patch application ci-pipelines-${ENV} \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

## 6) Smoke check

```bash
make smoke ENV=local

# Or directly:
oc -n openshift-gitops get applications
APP_HOST=$(oc -n bitiq-local get route bitiq-sample-app -o jsonpath='{.spec.host}')
echo "https://$APP_HOST" && curl -k "https://$APP_HOST/healthz" || true
```

## 7) Sample app images (public by default)

- The sample stack ships with two images:
  - Backend (`toy-service`) — defaults to `quay.io/paulcapestany/toy-service` with probes on `/healthz`.
  - Frontend (`toy-web`) — defaults to `quay.io/paulcapestany/toy-web` with probes on `/`.
- These live in `charts/bitiq-sample-app/values-*.yaml` under `backend.image` and `frontend.image` (plus `healthPath`, `hostPrefix`, and `service.port`).
- If you swap to your own images, ensure ports/probes line up; then hard refresh:
  ```bash
  oc -n openshift-gitops annotate application bitiq-sample-app-local argocd.argoproj.io/refresh=hard --overwrite
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
  oc -n openshift-gitops annotate application bitiq-sample-app-local argocd.argoproj.io/refresh=hard --overwrite
  ```
