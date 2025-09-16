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

Then connect the repo with write access via the Argo UI (SSO login):

```bash
ARGOCD_HOST=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')
open https://$ARGOCD_HOST   # or paste in browser
```

Argo UI → Settings → Repositories → Connect repo using HTTPS
- Repository URL: https://github.com/bitiq-io/gitops.git
- Username: any non‑empty (e.g., `git`)
- Password: fine‑grained PAT with Contents: Read/Write (repo‑scoped), or use an SSH deploy key with write access

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

oc -n openshift-gitops patch application ci-pipelines \
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

## 7) Sample app image (public by default)

- The sample app now uses a public image by default: `ghcr.io/traefik/whoami:v1.10.2` on port 8080 and probes `GET /` (200).
- These are set in `charts/bitiq-sample-app/values-common.yaml`:
  - `image.repository`, `image.tag`
  - `service.port: 8080`
  - `healthPath: "/"`
- If you swap to your own image, ensure the port and probe path line up; then hard refresh:
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
