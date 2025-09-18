# Local CI/CD (ENV=local) — End‑to‑End Guide

This guide captures the exact steps that work for running the full CI→CD flow on OpenShift Local (CRC): Tekton builds and pushes an image, Argo CD Image Updater writes the new tag back to Helm values, and Argo deploys the sample app.

Short on time? Run `make local-e2e` for an interactive helper that walks through the automation-friendly portions (bootstrap, RBAC, secrets) and leaves you only the external bits (webhook tunnel, git push).

When it prompts for the Git repo, it defaults to this GitOps repository URL (from `git remote get-url origin`). Only change it if Argo CD should track a fork or alternate remote.

Prereqs

- CRC running and you are logged in as cluster‑admin (`oc login ...`). Using the default `developer` user will trigger `Forbidden` errors when you interact with Argo CD or Tekton resources—either switch to `kubeadmin` or grant your user access, for example:

  ```bash
  oc adm policy add-role-to-user admin <your-user> -n openshift-gitops
  oc adm policy add-role-to-user admin <your-user> -n openshift-pipelines
  # or for full convenience (broad): oc adm policy add-cluster-role-to-user cluster-admin <your-user>
  ```

- This repo cloned and your shell in the repo root
- `argocd`, `helm`, and `ngrok` (or `cloudflared`) available locally

1) Bootstrap apps and operators

```bash
export ENV=local BASE_DOMAIN=apps-crc.testing
./scripts/bootstrap.sh
```

2) Allow Argo CD to manage app namespaces (dev convenience)

```bash
oc new-project bitiq-local || true
oc -n bitiq-local create rolebinding argocd-app-admin \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller || true
```

3) Image Updater token (recommended local account)

Using SSO users for API tokens often returns “account '<user>' does not exist”. Create a local Argo CD account for the updater and generate a token for it.

```bash
# Define local account + RBAC, then restart
oc -n openshift-gitops patch argocd openshift-gitops --type merge -p '{
  "spec":{
    "extraConfig":{"accounts.argocd-image-updater":"apiKey"},
    "rbac":{"policy":"g, kubeadmin, role:admin\n\ng, argocd-image-updater, role:admin\n\np, role:admin, *, *, *, allow\n","scopes":"[groups, sub, preferred_username, email]"}
  }
}'
oc -n openshift-gitops rollout restart deploy/openshift-gitops-server

# Login and generate token for the local account
ARGOCD_HOST=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')
argocd login "$ARGOCD_HOST" --sso --grpc-web --insecure
export ARGOCD_TOKEN=$(argocd account generate-token --grpc-web --account argocd-image-updater)

# Create/update the Secret and restart the updater
make image-updater-secret
```

4) Tekton prerequisites (namespace + webhook secret)

```bash
# Creates ns bitiq-ci, grants image pusher to pipeline SA, and creates the webhook secret
export GITHUB_WEBHOOK_SECRET=$(openssl rand -base64 32)
make tekton-setup GITHUB_WEBHOOK_SECRET="$GITHUB_WEBHOOK_SECRET"
```

5) Ensure ci-pipelines app is synced

The chart provides:
- Pipeline using Tekton Hub resolver tasks (no ClusterTasks needed)
- EventListener + TriggerBinding + TriggerTemplate
- ServiceAccount `pipeline` and RBAC (including cluster‑scope read for ClusterInterceptors)

```bash
oc -n openshift-gitops annotate application ci-pipelines argocd.argoproj.io/refresh=hard --overwrite
oc -n openshift-pipelines get pipeline bitiq-build-and-push
oc -n openshift-pipelines get eventlistener bitiq-listener
```

> These `oc` commands require the permissions noted in the prereqs. If you see `Forbidden`, re-run them as a cluster-admin or apply the RBAC grants above.

6) Expose the EventListener to GitHub (CRC)

GitHub cannot reach CRC directly. Use a tunnel and port‑forward:

```bash
# Terminal A: forward the EL service locally
oc -n openshift-pipelines port-forward svc/el-bitiq-listener 8080:8080

# Terminal B: expose via ngrok (or cloudflared)
ngrok http 8080   # copy the HTTPS URL shown

# Get the webhook secret value
oc -n openshift-pipelines get secret github-webhook-secret -o jsonpath='{.data.secretToken}' | base64 -d; echo
```

GitHub repo → Settings → Webhooks → Add webhook
- Payload URL: the ngrok HTTPS URL
- Content type: application/json
- Secret: the secret printed above
- Events: “Just the push event” (PRs are also supported)

7) Trigger a build and watch (Quay)

- Push a commit to the repo configured in `charts/ci-pipelines/values.yaml` (`pipeline.gitUrl`).
- The Pipeline tags the image with the commit SHA and pushes to Quay (`quay.io/paulcapestany/toy-service:<sha>`).
- Observe runs and logs:

```bash
oc -n openshift-pipelines get pipelineruns
tkn pr logs -L -f -n openshift-pipelines
```

8) Image Updater writes back and Argo syncs

- Tail Image Updater logs to see detection and Git write‑back:

```bash
oc -n openshift-gitops logs deploy/argocd-image-updater -f
```

- It updates `charts/bitiq-sample-app/values-local.yaml` with `image.tag: <sha>` → Argo syncs the app → Route should serve the new image.

Troubleshooting

- EventListener CrashLoopBackOff with ClusterInterceptor forbidden:
  - Fixed by cluster-scope RBAC included in the chart (`pipeline` SA can list `clusterinterceptors.triggers.tekton.dev`).
- Pipeline “custom task ref must specify apiVersion”:
  - Fixed by switching to Tekton Hub resolver tasks (no ClusterTasks needed).
- Buildah permission errors:
  - The chart binds the `pipeline` service account to the `privileged` SCC for local CRC builds. If you see `privileged: Invalid value: true`, ensure Argo synced the latest manifests or run `oc -n openshift-pipelines get rolebinding pipeline-privileged-scc`.
- Internal registry tag listing (Image Updater):
  - If tag discovery fails, add registry credentials for the updater, or temporarily point to a public registry. See README “Image updates & Git write-back”.
- Tekton git-clone fails with `/workspace/output/.git: Permission denied`:
  - Ensure Argo synced the latest chart revision; the Tekton manifests commit the pod security context via `taskRunTemplate.podTemplate.securityContext`.
  - The `pipeline` service account must be bound to the `pipelines-scc` SCC so Tekton’s affinity assistant can start.
  - Match `pipeline.fsGroup` in `charts/ci-pipelines/values.yaml` to the namespace `supplemental-groups` range (see `oc get project openshift-pipelines -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.supplemental-groups}'`).
- Image Updater CrashLoopBackOff with flag errors (`--log-level`, `--applications-namespace`, `--argocd-server`):
  - Ensure the deployment args include the `run` subcommand and only supported flags (`args: ["run", "--loglevel=…", "--argocd-server-addr=…"]`). The chart now uses the current flag names; resync the app if your pod still restarts.

Optional: set Quay credentials for the pipeline SA

```bash
export QUAY_USERNAME=<your-username>
export QUAY_PASSWORD=<your-token-or-password>
export QUAY_EMAIL=<your-email>
make quay-secret
```

Optional: point ci-pipelines at a feature branch for testing

```bash
oc -n openshift-gitops patch application ci-pipelines \
  --type merge -p '{"spec":{"source":{"targetRevision":"fix/pipelines-hub-and-sa"}}}'
oc -n openshift-gitops annotate application ci-pipelines argocd.argoproj.io/refresh=hard --overwrite
```

Links

- Runbook (general local setup): docs/LOCAL-RUNBOOK.md
- Tekton Triggers: https://tekton.dev/docs/triggers/
- Argo CD Image Updater: https://argocd-image-updater.readthedocs.io/
