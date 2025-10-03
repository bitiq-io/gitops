# Local Runbook (Ubuntu Server / Remote CRC)

This guide walks through running the full ENV=local GitOps workflow on a remote Ubuntu Server (22.04 or 24.04) by installing **OpenShift Local (CRC)** directly on the host. It includes virtualization prerequisites, CLI setup, bootstrap steps, and remote-friendly tips for webhooks and Route access.

> This mirrors the macOS guide (`docs/LOCAL-RUNBOOK.md`) but is tuned for headless Ubuntu hosts. CRC must still meet Red Hat’s hardware requirements: 4+ vCPUs, 12–16 GiB RAM, and ~50 GiB free disk.

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

- **OpenShift CLI (`oc`)**: download the matching release from Red Hat. Example (4.15):

  ```bash
  curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/oc-linux.tar.gz
  tar -xzf oc-linux.tar.gz oc kubectl
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

- **ngrok** or **cloudflared** (for GitHub webhooks). Example using ngrok:

  ```bash
  curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
  echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
  sudo apt update && sudo apt install -y ngrok
  ```

  Authenticate ngrok with `ngrok config add-authtoken <token>` (from the ngrok dashboard).

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
   oc login -u kubeadmin -p $(crc console --credentials | awk '/kubeadmin/ {print $2}') https://api.crc.testing:6443
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

## 5) Configure repo credentials and Image Updater token

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

## 6) Tekton prerequisites and webhook tunnel

1. Create the CI namespace, grant image pusher rights, and set the GitHub webhook secret (reuse existing helpers):

   ```bash
   export GITHUB_WEBHOOK_SECRET=$(openssl rand -base64 32)
   make tekton-setup GITHUB_WEBHOOK_SECRET="$GITHUB_WEBHOOK_SECRET"
   ```

2. Expose the EventListener route from the remote host:

   ```bash
   # Terminal A (server):
   oc -n openshift-pipelines port-forward svc/el-bitiq-listener 8080:8080

   # Terminal B (server):
   ngrok http 8080
   ```

   Copy the HTTPS URL into your GitHub webhook (content type JSON, secret = `$GITHUB_WEBHOOK_SECRET`).

3. To tail pipeline runs remotely:

   ```bash
   oc -n openshift-pipelines get pipelineruns
   tkn pr logs -f -n openshift-pipelines
   ```

## 7) Smoke tests

```bash
make smoke ENV=local
```

Or individually:

```bash
oc -n openshift-gitops get applications
oc -n bitiq-local get route
curl -k https://svc-api.apps-crc.testing/healthz
```

## 8) Remote Route access tips

- Routes (`*.apps-crc.testing`) resolve only inside the CRC VM. From your workstation, use SSH port forwarding to test services:

  ```bash
  # On your laptop
  ssh -L 8443:svc-api.apps-crc.testing:443 ubuntu@your-server
  curl -k https://localhost:8443/healthz
  ```

- Alternatively, run a reverse proxy on the server (e.g., Caddy or Nginx) bound to the public interface. Keep this off by default; only enable if you control firewall access.

## 9) Validation commands (pre-PR)

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
- **Git webhook timeouts**: confirm the ngrok tunnel is running and your server allows outbound HTTPS.

Refer back to `README.md`, `docs/LOCAL-CI-CD.md`, and `docs/LOCAL-SETUP.md` for deeper troubleshooting and background.

