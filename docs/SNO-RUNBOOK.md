# Single-Node OpenShift (ENV=sno) Runbook

This runbook walks through provisioning a Single-Node OpenShift (SNO) cluster and bootstrapping the `gitops` repository so that `ENV=sno` reaches the same CI/CD functionality as `ENV=local`. It assumes OpenShift Container Platform (OCP) 4.18, OpenShift GitOps 1.12+, and OpenShift Pipelines 1.16 (current as of 2025-09-26).

Important limitations

- SNO requires ignition/discovery ISO and day‑1 install assets created outside this repository (Assisted Installer or Agent‑based installer). This repo does not provision clusters or generate ignition.
- Because SNO cannot be emulated locally like CRC, we cannot “quick sanity‑check” `ENV=sno` without access to a real SNO cluster. Local and CI validation only cover chart/template correctness (`make template`, `make validate`).
- Treat this runbook as post‑install guidance. Provision the SNO cluster first, then use `./scripts/sno-preflight.sh` and the steps below.

## 1. Audience & Prerequisites

- **Use cases**: lab/demo clusters, edge deployments, or pre-prod environments where a single control-plane/worker node is acceptable.
- **Support statements**: required Red Hat subscriptions for OCP and for any catalog sources you rely on.
- **Hardware (minimum, per Red Hat guidance)**:
  - 8 physical CPU cores (16 vCPU recommended)
  - 32 GiB RAM minimum (64 GiB recommended for CI workloads)
  - 120 GiB SSD/NVMe for the root device (plus additional disks if installing OpenShift Data Foundation or LVM Storage)
- **Networking**:
  - Stable Layer 2/Layer 3 connectivity for the node
  - Outbound internet access for connected installs (registry, Operators, GitHub, Quay)
  - Ability to create DNS entries (wildcard `*.apps.<cluster-domain>`)
- **Local workstation**: `oc`, `helm`, `git`, `make`, and this repository cloned.

## 2. Provision the SNO Cluster

Choose the provisioning workflow that matches your connectivity model.

### 2.1 Assisted Installer (connected)

1. Log in to the Red Hat Hybrid Cloud Console and open **Red Hat OpenShift Cluster Manager**.
2. Create a **Single Node OpenShift** cluster. Provide:
   - Cluster name
   - Base domain (e.g. `example.io`)
   - Pull secret (download from cloud.redhat.com)
3. Download the discovery ISO, boot the target node, and wait for it to appear in the installer UI.
4. Approve the host, assign `control-plane` and `worker` roles (SNO uses both), and start installation.
5. After installation completes, download the `kubeadmin` credentials and record:
   - API server URL (`https://api.<cluster-name>.<base-domain>:6443`)
   - Application base domain (`apps.<cluster-name>.<base-domain>`)

> Reference: [Installing on a single node, Assisted Installer](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/installing_on_a_single_node)

### 2.2 Agent-based installer (disconnected or automated)

1. Follow the Agent-based installation flow to prepare the agent ISO, including:
   - Configuration manifests (cluster configuration, networking, machine configuration)
   - Optional ImageContentSourcePolicy or registry mirrors for disconnected installs
2. Boot the node with the agent ISO and monitor progress via `openshift-install agent wait-for install-complete`.
3. Capture the generated `kubeconfig` and cluster credentials.

> Reference: [Agent-based installation for SNO](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/installing_on_a_single_node/installation-single-node-agent-based)

## 3. Post-install Cluster Preparation

Run these steps after the cluster is reachable.

1. **Login and confirm cluster health**
   ```bash
   oc login https://api.<cluster-domain>:6443 -u kubeadmin -p '<PASSWORD>'
   oc get nodes
   ```
   Ensure the single node is `Ready` with roles `master,worker`.

2. **Configure storage**
   ```bash
   oc get storageclass
   ```
   - If no default storage class exists, install **OpenShift Data Foundation** or **LVM Storage** and set the desired class default:
     ```bash
     oc annotate storageclass <name> storageclass.kubernetes.io/is-default-class="true"
     ```
   - SNO requires block storage for Tekton PVCs and sample app data.

3. **Verify operator readiness**
   - SNO installs core operators automatically. Later steps will install OpenShift GitOps and OpenShift Pipelines via Helm chart `charts/bootstrap-operators`.
   - If your environment restricts cluster-wide default sources, mirror the required catalog sources before proceeding.

4. **DNS and Ingress**
   - Ensure a wildcard DNS record resolves to the node or ingress VIP: `*.apps.<cluster-domain> -> <node IP>`.
   - For homelab DNS, update your DNS server or `/etc/hosts` (for testing) with the specific routes you need, e.g. `svc-api.apps.<cluster-domain>`.

5. **TLS/Certificates**
   - If using custom CAs, add them to the cluster trust store and configure your workstation to trust the same CA before running GitOps scripts.

## 4. Clone repo & run SNO preflight

1. Clone your fork (or this repo) and change into it.
   ```bash
   git clone https://github.com/<your-org>/gitops.git
   cd gitops
   ```

2. Export environment variables for SNO:
   ```bash
   export ENV=sno
   export BASE_DOMAIN=apps.<cluster-domain>
   export TARGET_REV=main            # optional override
   export GIT_REPO_URL=$(git remote get-url origin)
   ```

3. Run the SNO preflight (added in this repo):
   ```bash
   ./scripts/sno-preflight.sh
   ```
   This script validates:
   - `oc` login status and API reachability
   - Exactly one Ready node
   - Default `StorageClass`
   - Required operator CatalogSources accessibility
   - Wildcard DNS or Route resolution for `${BASE_DOMAIN}`
   Resolve any failures before continuing.

## 5. Bootstrap GitOps stack for ENV=sno

1. Install OpenShift GitOps + Pipelines and the ApplicationSet:
   ```bash
   ENV=sno BASE_DOMAIN="$BASE_DOMAIN" ./scripts/bootstrap.sh
   ```
   The script:
   - Installs/ensures OpenShift GitOps and OpenShift Pipelines operators
   - Deploys the `bitiq-umbrella-by-env` ApplicationSet in `openshift-gitops`
   - Renders a single `bitiq-umbrella-sno` Application targeting `https://kubernetes.default.svc`

2. Watch the Application in Argo CD:
   ```bash
   oc -n openshift-gitops get application bitiq-umbrella-sno -w
   ```

3. Verify namespaces and Routes:
   ```bash
   oc get ns | grep bitiq-
   oc -n bitiq-sno get routes
   ```

## 6. Configure secrets & credentials (Vault operators)

The SNO environment now uses HashiCorp Vault Secrets Operator (VSO) and Vault Config Operator (VCO) by default. Bootstrap renders `vault-config-sno` (control plane, VCO) and `vault-runtime-sno` (runtime, VSO) Applications. Confirm the following before seeding credentials:

1. **Review env parameters** (optional override via `charts/argocd-apps/values.yaml`):
   ```yaml
   - name: sno
     vaultRuntimeEnabled: true
     vaultRuntimeAddress: https://vault-sno.vault.svc:8200      # replace with your Vault service DNS
     vaultRuntimeKubernetesMount: kubernetes
     vaultRuntimeRoleName: gitops-sno
     vaultConfigEnabled: true
     vaultConfigAddress: https://vault-sno.vault.svc:8200       # same endpoint the VCO will manage
     vaultConfigKubernetesHost: https://kubernetes.default.svc
     vaultConfigMountPath: kubernetes
     vaultConfigConnectionRole: kube-auth
     vaultConfigRoleName: gitops-sno
     vaultConfigPolicyName: gitops-sno
   ```
   Update the addresses/role names to match your Vault deployment. The umbrella chart injects these values into the VCO/VSO Helm releases.

2. **Verify Applications**
   ```bash
   oc -n openshift-gitops get application vault-config-sno vault-runtime-sno
   ```
   Both Applications should reach `Synced/Healthy`. If Vault is not yet reachable, pause sync until connectivity is restored to avoid repeated failures.

3. **Provision Vault configuration (VCO)**
   - Ensure Vault exposes the Kubernetes auth mount referenced above (typically `auth/kubernetes`).
   - After the `vault-config-sno` Application syncs, Vault will have:
     - `AuthEngineMount` + `KubernetesAuthEngineConfig` for the mount/path.
     - `Policy` granting read access to `gitops/data/*`.
     - `KubernetesAuthEngineRole` (`gitops-sno` by default) bound to the `default` ServiceAccount in `openshift-gitops`, `openshift-pipelines`, and `bitiq-sno`.
   - If you need to scope the policy, edit `charts/vault-config/values.yaml` or override via the Application parameters before syncing.

4. **Seed Vault secrets** (no `oc create secret`)
   ```bash
   export ARGOCD_TOKEN=<argocd-api-token>
   vault kv put gitops/data/argocd/image-updater token="$ARGOCD_TOKEN"

   # dockerconfigjson for the Tekton pipeline ServiceAccount
   vault kv put gitops/data/registry/quay \
     dockerconfigjson='{"auths":{"quay.io":{"auth":"<base64 user:token>"}}}'

   # GitHub webhook shared secret used by Tekton triggers
   vault kv put gitops/data/github/webhook token='<random-string>'

   # Optional runtime configs for the sample apps
   vault kv put gitops/data/services/toy-service/config FAKE_SECRET='<value>'
   vault kv put gitops/data/services/toy-web/config API_BASE_URL='https://svc-api.apps.<cluster-domain>'
   ```

5. **Wait for VSO to reconcile**
   ```bash
   oc -n openshift-gitops get vaultstaticsecrets.v1beta1.secrets.hashicorp.com
   oc -n openshift-pipelines get secrets quay-auth github-webhook-secret
   oc -n bitiq-sno get secrets toy-service-config toy-web-config
   ```
   The `vault-runtime-sno` Application renders `VaultStaticSecret` resources with `rolloutRestartTargets` for toy-service so deployments restart when Secret HMAC changes.

6. **Tekton integration**
   Once `quay-auth` exists, link it for image pulls/builds (idempotent):
   ```bash
   oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount
   ```

7. **Argo CD repo access**
   - Ensure OpenShift GitOps has write credentials for this repo (PAT or SSH key).
   - Validate with `argocd repo list` or a `git ls-remote` using the stored credentials. This is required for Image Updater write-back.

> Need to use ESO temporarily? Disable `vaultRuntimeEnabled`/`vaultConfigEnabled` for the env in `charts/argocd-apps/values.yaml` and consult the legacy appendix in `docs/PROD-SECRETS.md`. Avoid running ESO and VSO simultaneously—the repository’s guardrail policy and Argo Application gating block dual writers.

## 7. Smoke tests & validation

1. **Local template validation**
   ```bash
   make template
   make validate
   ```

2. **Cluster smoke**
   ```bash
   make smoke ENV=sno BASE_DOMAIN="$BASE_DOMAIN"
   ```
   Add `BOOTSTRAP=true` to re-run bootstrap inside the smoke script if desired.

3. **CI/CD verification**
   - Push a commit (or new tag) to the sample repositories tracked by the Tekton pipelines.
   - Confirm a `PipelineRun` succeeds (`oc -n openshift-pipelines get pipelineruns -w`).
   - Tail Image Updater logs:
     ```bash
     oc -n openshift-gitops logs deploy/argocd-image-updater -f --since=10m
     ```
  - Verify updated image tags in `charts/toy-service/values-sno.yaml` and `charts/toy-web/values-sno.yaml` via Argo CD commit history.

## 8. Troubleshooting

- **No default storage class**: install OpenShift Data Foundation or LVM Storage; set the class default before running Tekton pipelines.
- **Routes fail to resolve**: double-check wildcard DNS and that `BASE_DOMAIN` matches your ingress domain.
- **Pipeline fails to push image**: ensure Quay credentials are linked to `openshift-pipelines/pipeline` service account (VSO will reconcile `quay-auth`).
- **Image Updater authentication errors**: verify the Argo CD token permissions and that Argo CD has write access to the Git repo.
- **Cluster managed by central Argo CD**: set `clusterServer` in `charts/argocd-apps/values.yaml` to the external API URL and register the cluster via `argocd cluster add` before syncing.

## 9. References (September 2025)

- **Installing on a single node (OCP 4.18)**: https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/installing_on_a_single_node
- **OpenShift GitOps (OCP 4.18)**: https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/gitops
- **OpenShift Pipelines 1.16**: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.16
- **Argo CD Image Updater**: https://argocd-image-updater.readthedocs.io/en/stable/
- **OpenShift Data Foundation 4.18**: https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.18
