# Local Runbook (Ubuntu Server / Remote CRC)

This guide walks through running the full ENV=local GitOps workflow on a remote Ubuntu Server (22.04 or 24.04) by installing **OpenShift Local (CRC)** directly on the host. It includes virtualization prerequisites, CLI setup, bootstrap steps, and remote-friendly tips for webhooks and Route access.

> This mirrors the macOS guide (`docs/LOCAL-RUNBOOK.md`) and is tuned for Ubuntu Server. CRC must still meet Red Hat’s hardware requirements: 4+ vCPUs, 12–16 GiB RAM, and ~50 GiB free disk.

## Quick Interactive Setup

Short on time? Use the interactive helper to bootstrap, grant RBAC, and create the common secrets/credentials in one guided flow.

```bash
make local-e2e
# or
ENV=local BASE_DOMAIN=apps-crc.testing ./scripts/local-e2e-setup.sh
```

Prerequisites:
- You are logged in as cluster-admin: `oc login -u kubeadmin -p <pass> https://api.crc.testing:6443`
- `argocd` CLI is installed and you can log in to the OpenShift GitOps route (`--sso --grpc-web --insecure`).

What it covers:
- Runs `scripts/bootstrap.sh` (operators + ApplicationSet + umbrella app)
- Ensures ESO is installed (via bootstrap) and prompts you to seed Vault via `make dev-vault`
- Grants Argo CD controller admin in `bitiq-local` and `openshift-pipelines`
- Prompts to add Argo CD repo credentials and `argocd-image-updater-secret`

For full context and follow-ups (webhook exposure, build triggers, logs), see `docs/LOCAL-CI-CD.md`.

### Headless Fast Path (non-interactive)

When running on a headless server, you can avoid prompts and `argocd` CLI login by providing credentials via env vars. The helper will seed all required secrets and repo credentials for you and then refresh/wait for apps to sync.

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
- The script runs `bootstrap.sh` with `SKIP_APP_WAIT=true`, then configures RBAC/secrets and forces an Argo CD refresh before waiting for Healthy/Synced.
- If you provide `GH_PAT`, it is accepted as an alias for `ARGOCD_REPO_PASSWORD`/`ARGOCD_REPOCREDS_PASSWORD`.
- If a secret already exists, the helper leaves it as-is unless updated interactively (when `FAST_PATH` is not set).

## 0) Host prerequisites

1. Confirm virtualization support (KVM):

   ```bash
   lscpu | grep Virtualization
   lsmod | grep kvm
   ```

   Your CPU must advertise VT-x/AMD-V and the `kvm` modules should be loaded. Enable virtualization in the BIOS if those checks fail.

2. Install KVM/libvirt packages and start the daemon:

   ```bash
   sudo apt update
   sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst bridge-utils dnsmasq
   sudo systemctl enable --now libvirtd
   ```

3. Add your login user to the required groups, then log out/in (or `newgrp`):

   ```bash
   sudo usermod -aG libvirt,libvirt-qemu $USER
   newgrp libvirt
   ```

4. Optional: disable telemetry (matches macOS workflow):

   ```bash
   crc config set consent-telemetry no
   ```

## 1) Install CLI tooling

- **OpenShift CLI (`oc`)**: download the matching release from Red Hat. Example (4.19):

  ```bash
  curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.19/openshift-client-linux.tar.gz
  # Validate the archive looks correct (optional but recommended)
  file openshift-client-linux.tar.gz
  tar -tzf openshift-client-linux.tar.gz | grep -E '^(oc|kubectl)$'
  # Extract the oc and kubectl binaries
  tar -xzf openshift-client-linux.tar.gz oc kubectl
  sudo mv oc kubectl /usr/local/bin/
  oc version
  ```

- **Helm**:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  ```

- **Argo CD CLI** (needed for repo creds/token helpers):

  ```bash
  ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | jq -r .tag_name)
  curl -LO https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64
  sudo install argocd-linux-amd64 /usr/local/bin/argocd
  argocd version --client
  ```

- Webhook exposure: choose one
  - Dynamic DNS on your server (recommended): no extra tool needed. You will bind the port-forward to `0.0.0.0` and open port `8080/tcp` on the host firewall.
  - Tunneling tool (optional alternative): **ngrok** or **cloudflared**.

  Example ngrok install (only if you opt for a tunnel):

  ```bash
  curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
  echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
  sudo apt update && sudo apt install -y ngrok
  ngrok config add-authtoken <token>
  ```

## 2) Install and start OpenShift Local (CRC)

1. Download the latest CRC tarball for Linux from https://developers.redhat.com/content-gateway/file/openshift-local/ (Red Hat login required). Example:

   ```bash
   tar -xvf crc-linux-amd64.tar.xz
   sudo install crc-linux-*-amd64/crc /usr/local/bin/
   crc version
   ```

2. Configure recommended resources and trust the bundle:

   ```bash
   crc setup
   crc config set memory 16384
   crc config set cpus 6
   crc config set disk-size 120
   ```

3. Start the cluster:

   ```bash
   crc start
   ```

   Keep the startup output; it prints the kubeadmin password and suggested `eval $(crc oc-env)` command.

4. Export `oc` environment vars and log in:

   ```bash
   eval "$(crc oc-env)"
   # Extract kubeadmin password from CRC credentials output
   KUBEADMIN_PASSWORD=$(crc console --credentials | awk -F': *' '/Password/ {print $2; exit}')
   oc login -u kubeadmin -p "$KUBEADMIN_PASSWORD" https://api.crc.testing:6443
   ```

## 3) Clone the GitOps repo

```bash
git clone https://github.com/bitiq-io/gitops.git
cd gitops
```

If you plan to push changes, clone your fork and configure `origin` accordingly.

## 4) Bootstrap ENV=local

```bash
export ENV=local
./scripts/bootstrap.sh
```

- Defaults now set Image Updater’s platform filter to `linux/amd64`, which matches Ubuntu hosts.
- If you ever need to target `linux/arm64`, set `PLATFORMS_OVERRIDE=linux/arm64` when running the script.
- Tekton Results is disabled by default on ENV=local (via `TektonConfig.spec.result.disabled=true`) to avoid CRC’s HostPath PVs allocating ~all disk for the Results Postgres PVC. If you need Results locally, opt in:
  - Keep Results: `TEKTON_RESULTS=true ./scripts/bootstrap.sh`
  - Optionally shrink storage (if supported by your operator): `TEKTON_RESULTS=true TEKTON_RESULTS_STORAGE=5Gi ./scripts/bootstrap.sh`

## 5) Seed Vault secrets (ENV=local)

Run the helper target to stand up a dev-mode Vault (`vault-dev` namespace), configure Kubernetes auth, seed sample credentials under `gitops/data/...`, create the `vault-auth` ServiceAccount, and install/refresh the `eso-vault-examples` Helm release pointing at that Vault:

```bash
make dev-vault
```

Re-run the target after modifying values or updating credentials. When you are done with your local cluster, clean up with:

```bash
make dev-vault-down
```

Verify the secrets appear in the expected namespaces (Argo CD, Tekton, bitiq-local) using the commands from [PROD-SECRETS](PROD-SECRETS.md).

## 6) Configure repo credentials and Image Updater token

1. OpenShift GitOps route (for CLI/API):

   ```bash
   ARGOCD_HOST=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')
   argocd login "$ARGOCD_HOST" --sso --grpc-web --insecure
   ```

2. Provide repository credentials with write access (PAT or SSH). Example for GitHub HTTPS:

   ```bash
   export GH_PAT=<personal-access-token>
   argocd repo add https://github.com/bitiq-io/gitops.git \
     --username <github-username> \
     --password "$GH_PAT" --grpc-web
   ```

3. Generate an Argo CD API token (recommended: dedicated `argocd-image-updater` account per README/LOCAL-CI-CD). Seed the secret:

   ```bash
   export ARGOCD_TOKEN=$(argocd account generate-token --grpc-web --account argocd-image-updater)
   make image-updater-secret
   ```



## 7) Tekton prerequisites and webhook exposure

1. Create the CI namespace, grant image pusher rights, and set the GitHub webhook secret (reuse existing helpers):

   ```bash
   export GITHUB_WEBHOOK_SECRET=$(openssl rand -base64 32)
   make tekton-setup GITHUB_WEBHOOK_SECRET="$GITHUB_WEBHOOK_SECRET"
   ```

   Grant Argo CD permission to create Tekton resources in `openshift-pipelines` (prevents Forbidden errors while syncing `ci-pipelines-local`):

   ```bash
   oc -n openshift-pipelines create rolebinding argocd-app-admin \
     --clusterrole=admin \
     --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller || true
   ```

   EventListener ServiceAccount note:

   - By default, the chart lets Tekton Triggers auto-manage the EventListener ServiceAccount and bind the required RBAC. This is recommended for local runs.
   - If you explicitly set `triggers.serviceAccountName` (e.g., to `pipeline`), grant it Triggers permissions or the EventListener will receive webhooks but not create PipelineRuns:
     `oc -n openshift-pipelines create rolebinding el-bitiq-listener-pipeline --clusterrole=tekton-triggers-eventlistener-clusterrole --serviceaccount=openshift-pipelines:pipeline || true`
   - After changing RBAC/SA, restart the EventListener: `oc -n openshift-pipelines rollout restart deploy/el-bitiq-listener`.

2. Expose the EventListener from the remote host (choose one):

   Option A — Dynamic DNS (no tunnel; recommended on a remote server)

   ```bash
   # Choose a host port (default 8080). If 8080 is in use (e.g., nginx), pick another like 18080.
   HOST_PORT=8080   # or 18080
   sudo ufw allow ${HOST_PORT}/tcp || true

   # Bind the port-forward to all interfaces so GitHub can reach it via your DDNS name
   oc -n openshift-pipelines port-forward --address 0.0.0.0 svc/el-bitiq-listener ${HOST_PORT}:8080
   ```

   - Payload URL in your GitHub webhook: `http://<your-ddns-name>:<HOST_PORT>`
   - Content type: `application/json`
   - Secret: `$GITHUB_WEBHOOK_SECRET`
   - Note: GitHub accepts HTTP. If your org enforces HTTPS, front port 8080 with a reverse proxy (e.g., Caddy/NGINX) that terminates TLS and proxies to `127.0.0.1:8080`.

   Option B — Tunnel (ngrok or cloudflared)

   ```bash
   # Terminal A (server): forward the service locally (change HOST_PORT if 8080 is in use)
   HOST_PORT=8080   # or 18080
   oc -n openshift-pipelines port-forward svc/el-bitiq-listener ${HOST_PORT}:8080

   # Terminal B (server): run the tunnel and copy the HTTPS URL
   ngrok http 8080
   ```

   - Payload URL in your GitHub webhook: the ngrok/cloudflared HTTPS URL that forwards to `<HOST_PORT>`
   - Content type: `application/json`
   - Secret: `$GITHUB_WEBHOOK_SECRET`

3. To tail pipeline runs remotely:

   ```bash
   oc -n openshift-pipelines get pipelineruns
   tkn pr logs -f -n openshift-pipelines
   ```

## 8) Smoke tests

```bash
make smoke ENV=local
```

Or individually:

```bash
oc -n openshift-gitops get applications
oc -n bitiq-local get route
curl -k https://svc-api.apps-crc.testing/healthz
```

## 9) Remote Route access tips

- Routes (`*.apps-crc.testing`) resolve only inside the CRC VM. From your workstation, use SSH port forwarding to test services:

  ```bash
  # On your laptop
  ssh -L 8443:svc-api.apps-crc.testing:443 ubuntu@your-server
  curl -k https://localhost:8443/healthz
  ```

- Alternatively, run a reverse proxy on the server (e.g., Caddy or Nginx) bound to the public interface. Keep this off by default; only enable if you control firewall access.

## 10) Validation commands (pre-PR)

Run the standard checks before committing changes:

```bash
make lint
make template
make validate
```

## Troubleshooting

- **`crc start` fails with `libvirt` errors**: ensure your user is in the `libvirt` group and log out/in. Check `systemctl status libvirtd`.
- **`oc login` certificate warnings**: CRC uses self-signed certs; use `--insecure-skip-tls-verify` or trust the CA.
- **Pipeline image push forbidden**: rerun `make tekton-setup`; verify the `pipeline` service account has `system:image-pusher` in `bitiq-ci`.
- **Image Updater skips tags**: confirm the platform filter matches your architecture (override via `PLATFORMS_OVERRIDE`).
- **Tekton git-clone fails with `/workspace/output/.git: Permission denied`**:
  - Cause: the Task pod runs with a random UID under OpenShift’s restricted SCC. The workspace PVC needs a writable fsGroup.
  - Fix: `./scripts/bootstrap.sh` auto‑detects a valid fsGroup for the `openshift-pipelines` namespace and applies it to the pipelines chart. Re‑run bootstrap after installing operators.
  - Override (if needed): `TEKTON_FSGROUP=<gid> ./scripts/bootstrap.sh`. To find a valid value, run `oc get project openshift-pipelines -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.supplemental-groups}'` and use the first number of the printed range.
- **Git webhook timeouts**:
  - Dynamic DNS path: ensure the port-forward is listening on `0.0.0.0:8080` and the host firewall/security group allows inbound `8080/tcp`.
  - Tunnel path: confirm the tunnel is running and the copied URL matches your webhook.

Refer back to `README.md`, `docs/LOCAL-CI-CD.md`, and `docs/LOCAL-SETUP.md` for deeper troubleshooting and background.

### Tekton git-clone fsGroup — Verification & Workaround

- End‑to‑end verification (after re‑running `./scripts/bootstrap.sh`):
  - ApplicationSet has the generator field:
    `oc -n openshift-gitops get applicationset bitiq-umbrella-by-env -o yaml | rg -n 'tektonFsGroup'`
  - Umbrella → ci-pipelines Application includes the Helm value:
    `oc -n openshift-gitops get app ci-pipelines-local -o yaml | rg -n 'ciPipelines.fsGroup'`
  - TriggerTemplate injects `fsGroup` into TaskRun pods:
    `oc -n openshift-pipelines get triggertemplate bitiq-web-build-and-push-template -o yaml | rg -n 'taskRunTemplate|podTemplate|fsGroup'`

- Immediate workaround (if you cannot re‑bootstrap yet):
  `oc -n openshift-pipelines patch triggertemplate bitiq-web-build-and-push-template --type='json' -p='[{"op":"add","path":"/spec/resourcetemplates/0/spec/taskRunTemplate/podTemplate/securityContext","value":{"fsGroup":1000660000}}]'`

- Note: Older repo revisions missed wiring `tektonFsGroup` in the ApplicationSet generator, which prevented `fsGroup` from reaching Tekton. Pull latest, rerun `./scripts/bootstrap.sh`, and re‑trigger your PipelineRun.
