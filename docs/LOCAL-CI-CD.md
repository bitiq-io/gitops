# Local CI/CD (ENV=local) — End‑to‑End Guide

This guide captures the exact steps that work for running the full CI→CD flow on OpenShift Local (CRC): Tekton builds and pushes an image, Argo CD Image Updater writes the new tag back to Helm values, and Argo deploys the sample app.

Short on time? Run `make local-e2e` for an interactive helper that walks through the automation-friendly portions (bootstrap, RBAC, secrets) and leaves you only the external bits (webhook exposure, git push).

When it prompts for the Git repo, it defaults to this GitOps repository URL (from `git remote get-url origin`). Only change it if Argo CD should track a fork or alternate remote.

Prereqs

- CRC running and you are logged in as cluster‑admin (`oc login ...`). Using the default `developer` user will trigger `Forbidden` errors when you interact with Argo CD or Tekton resources—either switch to `kubeadmin` or grant your user access, for example:

  ```bash
  oc adm policy add-role-to-user admin <your-user> -n openshift-gitops
  oc adm policy add-role-to-user admin <your-user> -n openshift-pipelines
  # or for full convenience (broad): oc adm policy add-cluster-role-to-user cluster-admin <your-user>
  ```

- This repo cloned and your shell in the repo root
- `argocd` and `helm` available locally
- Webhook exposure: either a dynamic DNS hostname pointing to your server with port `8080/tcp` open, or a tunneling tool (ngrok/cloudflared)

Defaults worth knowing

- Platform filter for Image Updater: ENV=local, ENV=sno, and ENV=prod now default to `linux/amd64`. These are set per env in `charts/argocd-apps/values.yaml` under `envs[].platforms` and passed into the umbrella chart. If your local cluster is arm64 (for example, Apple Silicon CRC), either publish multi‑arch images or override `local` to `linux/arm64`. During bootstrap you can set `PLATFORMS_OVERRIDE=linux/arm64 ENV=local ./scripts/bootstrap.sh` instead of editing the chart.
- Frontend image updates are enabled for `local`. Make sure the `toy-web` image is published to Quay (or set `enableFrontendImageUpdate: false` if you want to skip the frontend flow). If your repository is private, add a pull secret via `imageUpdater.pullSecret` so tag listing works.

Remote server notes

- CRC Routes resolve only on the host; to test them from elsewhere use SSH port forwarding (e.g., `ssh -L 8443:svc-api.apps-crc.testing:443`).
- Run the port-forward directly on the server so GitHub can reach the Tekton EventListener. With dynamic DNS, bind to `0.0.0.0` and open port `8080/tcp`; otherwise use a tunnel (ngrok/cloudflared).
- The Ubuntu-specific runbook (`docs/LOCAL-RUNBOOK-UBUNTU.md`) covers CLI installs and remote webhook tips in more detail.

1) Bootstrap apps and operators

```bash
export ENV=local BASE_DOMAIN=apps-crc.testing
./scripts/bootstrap.sh
```

2) Allow Argo CD to manage namespaces (dev convenience)

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

5) Ensure ci-pipelines-${ENV} is synced

The chart provides:
- Two Tekton Pipelines (backend + frontend) using Hub resolver tasks (no ClusterTasks needed)
- TriggerTemplates + TriggerBindings per pipeline, wired into a single EventListener with repo-based routing
- ServiceAccount `pipeline` and RBAC (including cluster‑scope read for ClusterInterceptors)
- Optional test phase driven by each pipeline’s `runTests`: backend runs `go test ./...`; frontend runs `npm ci && npm test -- --watch=false` using configurable builder images.

```bash
oc -n openshift-gitops annotate application ci-pipelines-${ENV} argocd.argoproj.io/refresh=hard --overwrite
oc -n openshift-pipelines get pipeline bitiq-build-and-push
oc -n openshift-pipelines get pipeline bitiq-web-build-and-push
oc -n openshift-pipelines get eventlistener bitiq-listener
```

> These `oc` commands require the permissions noted in the prereqs. If you see `Forbidden`, re-run them as a cluster-admin or apply the RBAC grants above.

6) Expose the EventListener to GitHub (CRC)

GitHub cannot reach CRC Routes directly. Choose one option to expose the EventListener:

Option A — Dynamic DNS (no tunnel)

```bash
# Bind the port-forward to all interfaces (run on the server)
# Choose a host port (default 8080). If 8080 is in use (e.g., nginx), pick another like 18080.
HOST_PORT=8080   # or 18080
oc -n openshift-pipelines port-forward --address 0.0.0.0 svc/el-bitiq-listener ${HOST_PORT}:8080

# Get the webhook secret value
oc -n openshift-pipelines get secret github-webhook-secret -o jsonpath='{.data.secretToken}' | base64 -d; echo
```

GitHub repo → Settings → Webhooks → Add webhook
- Payload URL: http://<your-ddns-hostname>:<HOST_PORT>
- Content type: application/json
- Secret: the secret printed above
- Events: “Just the push event” (PRs are also supported)

Option B — Tunnel (ngrok or cloudflared)

```bash
# Terminal A: forward the EL service locally (choose HOST_PORT if 8080 is in use)
HOST_PORT=8080   # or 18080
oc -n openshift-pipelines port-forward svc/el-bitiq-listener ${HOST_PORT}:8080

# Terminal B: expose via ngrok (or cloudflared)
ngrok http ${HOST_PORT}   # copy the HTTPS URL shown

# Get the webhook secret value
oc -n openshift-pipelines get secret github-webhook-secret -o jsonpath='{.data.secretToken}' | base64 -d; echo
```

GitHub repo → Settings → Webhooks → Add webhook
- Payload URL: the tunnel HTTPS URL
- Content type: application/json
- Secret: the secret printed above
- Events: “Just the push event” (PRs are also supported)

7) Trigger a build and watch (Quay)

- Push a commit to either repo configured under `pipelines[].gitUrl` in `charts/ci-pipelines/values.yaml`.
- The Pipeline tags the image with the commit SHA and pushes to Quay (`quay.io/paulcapestany/toy-service:<sha>`).
- Observe runs and logs:

The sample app Helm values (`charts/bitiq-sample-app/values-local.yaml`) default the image to `quay.io/paulcapestany/toy-service:latest`; Argo CD Image Updater rewrites the tag to each commit SHA once the pipeline publishes it.

```bash
oc -n openshift-pipelines get pipelineruns
tkn pr logs -L -f -n openshift-pipelines
```

8) Image Updater writes back and Argo syncs

- Tail Image Updater logs to see detection and Git write‑back:

```bash
oc -n openshift-gitops logs deploy/argocd-image-updater -f
```

- It updates `charts/bitiq-sample-app/values-local.yaml` with the backend/frontend tags → Argo syncs the app → Routes (`svc-api.*` and `svc-web.*`) should serve the refreshed images.

Troubleshooting

- EventListener CrashLoopBackOff with ClusterInterceptor forbidden:
  - Fixed by cluster-scope RBAC included in the chart (`pipeline` SA can list `clusterinterceptors.triggers.tekton.dev`).
- Pipeline “custom task ref must specify apiVersion”:
  - Fixed by switching to Tekton Hub resolver tasks (no ClusterTasks needed).
- EventListener ServiceAccount & RBAC:
  - Default behavior: the chart now lets Tekton Triggers auto-manage the EventListener ServiceAccount and bind the required RBAC. Do not set `triggers.serviceAccountName` unless you know you need a specific SA.
  - If you explicitly set an SA (e.g., `pipeline`), you must grant it Triggers permissions; otherwise the EventListener will receive webhooks but fail to create PipelineRuns. Example one-liner:
    `oc -n openshift-pipelines create rolebinding el-bitiq-listener-pipeline --clusterrole=tekton-triggers-eventlistener-clusterrole --serviceaccount=openshift-pipelines:pipeline || true`
  - After changing RBAC or the SA, restart the EventListener: `oc -n openshift-pipelines rollout restart deploy/el-bitiq-listener`.
  
- Webhook received but no PipelineRun created (Trigger started/done logged):
  - Symptom: You see events like `dev.tekton.event.triggers.started/done` on the EventListener, and GitHub shows the webhook as delivered, but no `PipelineRun` appears.
  - Likely cause: The `TriggerBinding` for the target pipeline is missing. The EventListener references `<pipeline.name>-binding`; without it, params won’t pass into the `TriggerTemplate`.
  - Verify:
    - `oc -n openshift-pipelines get triggerbinding`
    - Ensure both `bitiq-build-and-push-binding` and `bitiq-web-build-and-push-binding` exist (or bindings for any new pipelines you add).
    - `oc -n openshift-pipelines get eventlistener bitiq-listener -o yaml | rg -n 'bindings:|ref: .*binding'`
  - Fix:
    - The chart now renders a `TriggerBinding` per pipeline from `charts/ci-pipelines/templates/trigger-bindings.yaml`.
    - If you added a new pipeline, ensure it’s listed under `.Values.pipelines` with a unique `name`. The binding `<name>-binding` will be generated automatically.
    - Resync `ci-pipelines-${ENV}` and retry the push.
- Buildah permission errors:
  - The chart binds the `pipeline` service account to the `privileged` SCC for local CRC builds. If you see `privileged: Invalid value: true`, ensure Argo synced the latest manifests or run `oc -n openshift-pipelines get rolebinding pipeline-privileged-scc`.
- Internal registry tag listing (Image Updater):
  - If tag discovery fails, add registry credentials for the updater, or temporarily point to a public registry. See README “Image updates & Git write-back”.
- Tekton git-clone fails with `/workspace/output/.git: Permission denied`:
  - Ensure Argo synced the latest chart revision; the Tekton manifests commit the pod security context via `taskRunTemplate.podTemplate.securityContext`.
  - The `pipeline` service account must be bound to the `pipelines-scc` SCC so Tekton’s affinity assistant can start.
  - Match `pipeline.fsGroup` in `charts/ci-pipelines/values.yaml` to the namespace `supplemental-groups` range (see `oc get project openshift-pipelines -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.supplemental-groups}'`).
- git-clone fails with "/workspace/.../.git: Permission denied":
  - Cause: Tekton Task pods run as a random UID under the OpenShift restricted SCC. If the workspace PVC isn’t group‑writable, the `git-clone` Task can’t create `.git`.
  - Fix: `scripts/bootstrap.sh` now auto‑detects an allowed fsGroup for the `openshift-pipelines` namespace and passes it to the pipelines chart. If needed, override explicitly: `TEKTON_FSGROUP=<gid> ./scripts/bootstrap.sh`.
  - Manual check: `oc get project openshift-pipelines -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.supplemental-groups}'` and use the first number of the `<start>/<size>` or `<start>-<end>` range.
- CRC/HostPath PVCs balloon to ~cluster disk size (e.g., 499Gi):
  - On OpenShift Local (CRC), the `crc-csi-hostpath-provisioner` may provision PVs with a very large capacity. You might see the Tekton Results Postgres PVC and even ephemeral PipelineRun PVCs show ~the entire CRC disk size.
  - These PVs are typically thin‑provisioned. However, they consume the quota visually and are inconvenient for local runs.
  - If you don’t need Tekton Results locally, disable it and delete its DB PVC:
    1) Find the `TektonConfig` (namespace may vary):
       ```bash
       oc get tektonconfigs.operator.tekton.dev -A
       ```
    2) Disable Results (OpenShift Pipelines 1.20+):
       ```bash
       # Many clusters use a cluster-scoped TektonConfig named 'config'
       oc patch tektonconfig config --type merge -p '{"spec":{"result":{"disabled":true}}}'
       # If your TektonConfig is namespaced, add -n <ns>
       ```
    3) Remove the Results DB StatefulSet and PVCs (recreated only if Results is re‑enabled):
       ```bash
       oc -n openshift-pipelines delete statefulset -l app.kubernetes.io/name=tekton-results-postgres || true
       oc -n openshift-pipelines delete pvc -l app.kubernetes.io/name=tekton-results-postgres || true
       ```
  - If you do want Results, reduce its storage before installation or after by editing the corresponding CR (fields vary by operator). Some operators accept storage via `addon.params` on the TektonConfig; set it small (e.g., 1–5Gi), then delete/recreate the StatefulSet to pick up the new size:
    ```bash
    oc patch tektonconfig config --type merge -p '{"spec":{"addon":{"params":[{"name":"tekton-results-postgres-storage","value":"5Gi"}]}}}' || true
    oc -n openshift-pipelines delete statefulset -l app.kubernetes.io/name=tekton-results-postgres
    ```
  - Some clusters use a separate `TektonResult` CR named `result`. Deleting that CR disables Results until re-enabled by the operator:
    ```bash
    oc delete tektonresults.operator.tekton.dev result || oc delete tektonresults result
    ```
  - For PipelineRun workspace PVCs created via this repo’s chart, the request is already small (2Gi). If a bound PV shows ~499Gi on CRC, it is a quirk of the HostPath provisioner and not the request from the PipelineRun. You can safely delete leftover `pvc-<random>` claims once the run completes.
- Image Updater CrashLoopBackOff with flag errors (`--log-level`, `--applications-namespace`, `--argocd-server`):
  - Ensure the deployment args include the `run` subcommand and only supported flags (`args: ["run", "--loglevel=…", "--argocd-server-addr=…"]`). The chart now uses the current flag names; resync the app if your pod still restarts.
- Image Updater forbidden on Applications:
  - The chart now binds the service account with a ClusterRole so it can list `applications.argoproj.io` cluster-wide; resync `image-updater` if you see `applications.argoproj.io is forbidden` after upgrades.
- Image Updater "Invalid Semantic Version" errors:
  - Tags from the pipeline are commit SHAs, so the Application annotations pin the update strategy to `newest-build`. If a future release requires explicit tag filters, add `app.allow-tags` back with the appropriate regex.

FsGroup verification for git-clone

- After re‑running `./scripts/bootstrap.sh`, confirm fsGroup propagates end‑to‑end:
  - ApplicationSet generator includes `tektonFsGroup`:
    `oc -n openshift-gitops get applicationset bitiq-umbrella-by-env -o yaml | rg -n 'tektonFsGroup'`
  - `ci-pipelines-<env>` Application Helm values include `ciPipelines.fsGroup`:
    `oc -n openshift-gitops get app ci-pipelines-local -o yaml | rg -n 'ciPipelines.fsGroup'`
  - TriggerTemplate sets `taskRunTemplate.podTemplate.securityContext.fsGroup`:
    `oc -n openshift-pipelines get triggertemplate bitiq-web-build-and-push-template -o yaml | rg -n 'taskRunTemplate|podTemplate|fsGroup'`

- Workaround (if you cannot re‑bootstrap yet):
  `oc -n openshift-pipelines patch triggertemplate bitiq-web-build-and-push-template --type='json' -p='[{"op":"add","path":"/spec/resourcetemplates/0/spec/taskRunTemplate/podTemplate/securityContext","value":{"fsGroup":1000660000}}]'`
- Image Updater skips tags due to platform mismatch:
  - The umbrella chart now exposes `imageUpdater.platforms` (default `linux/amd64`). If you build on Apple Silicon and push arm64-only tags, either:
    - Publish multi-arch images: use `scripts/buildx-multiarch.sh` to push `linux/amd64,linux/arm64`, or
    - Override the platform for your env by setting `imageUpdater.platforms: linux/arm64` in the umbrella chart values for that environment.
  - Keeping the filter aligned with your cluster node arch avoids pods failing with `no matching manifest for linux/amd64`.
- Image Updater write-back path resolves incorrectly:
  - `write-back-target` is relative to the Application's source path unless you prefix it with `/`. The chart now uses `/charts/bitiq-sample-app/values-<env>.yaml`; resync the umbrella app if you previously rendered a double `charts/` path.

Optional: set Quay credentials for the pipeline SA

```bash
export QUAY_USERNAME=<your-username>
export QUAY_PASSWORD=<your-token-or-password>
export QUAY_EMAIL=<your-email>
make quay-secret
```

Optional: point the pipelines Application at a feature branch for testing

```bash
oc -n openshift-gitops patch application ci-pipelines-${ENV} \
  --type merge -p '{"spec":{"source":{"targetRevision":"feature/pipelines-updates"}}}'
oc -n openshift-gitops annotate application ci-pipelines-${ENV} argocd.argoproj.io/refresh=hard --overwrite
```

Links

- Runbook (general local setup): docs/LOCAL-RUNBOOK.md
- Tekton Triggers: https://tekton.dev/docs/triggers/
- Argo CD Image Updater: https://argocd-image-updater.readthedocs.io/
