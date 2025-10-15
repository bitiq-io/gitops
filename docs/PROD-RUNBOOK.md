# Production OCP (ENV=prod) Runbook

This runbook documents how to bootstrap the `gitops` repository onto a production-grade OpenShift Container Platform (OCP) 4.19 cluster using the in-cluster Argo CD model. It parallels the local and SNO flows so that `ENV=prod` reaches full CI/CD parity. Current component baselines (September 29, 2025): OCP 4.19, OpenShift GitOps 1.18+, OpenShift Pipelines 1.20+, Argo CD Image Updater v0.16.

## 1. Audience & Prerequisites

- **Use cases**: Staging or production OCP clusters that require GitOps-driven deployments with Tekton CI and automated image promotion.
- **Cluster requirements** (follow Red Hat production sizing guidance):
  - Minimum three control plane nodes and at least two worker nodes sized for your workloads.
  - Default storage class that supports ReadWriteOnce PVCs for Tekton pipelines and sample app state.
  - Wildcard DNS record for applications: `*.apps.<cluster-domain>` resolves to the ingress load balancer VIP.
  - Outbound connectivity to Git hosting, container registry (e.g., Quay.io), and Red Hat Operator Catalog sources.
- **Workstation**: `oc`, `helm` 3.14+, `git`, `make`, and this repository cloned.
- **Access**: Cluster-admin privileges on the target cluster; credentials to write to the Git repository and container registry.
- **Security**: Secrets are managed via Vault operators — HashiCorp Vault Secrets Operator (VSO) for runtime delivery and Red Hat COP Vault Config Operator (VCO) for control-plane configuration. Never commit secrets to Git or create them manually with `oc`.

## 2. Decide operator channels (GitOps & Pipelines)

OpenShift GitOps and OpenShift Pipelines are installed via `charts/bootstrap-operators`. The repo pins channels known to support OCP 4.19:

1. GitOps channel `gitops-1.18` (supports OCP 4.14, 4.16-4.19 per [GitOps 1.18 compatibility matrix][gitops-1-18]).
2. Pipelines channel `pipelines-1.20` (supports OCP 4.15-4.19 per [Pipelines 1.20 compatibility matrix][pipelines-1-20]).
3. If Red Hat publishes newer GA channels for OCP 4.19, update `charts/bootstrap-operators/values.yaml` accordingly and document the change in your PR (per `AGENTS.md`).

[gitops-1-18]: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/release_notes/gitops-release-notes#GitOps-compatibility-support-matrix_gitops-release-notes
[pipelines-1-20]: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20/html/release_notes/op-release-notes-1-20#compatibility-support-matrix_op-release-notes

## 3. Cluster readiness checklist

1. **Login and verify nodes**
   ```bash
   oc login https://api.<cluster-domain>:6443 -u <admin>
   oc get nodes -o wide
   ```
   - Ensure all control plane and worker nodes report `Ready`.
2. **Default storage class**
   ```bash
   oc get storageclass
   ```
   - Mark the intended class as default if needed:
     ```bash
     oc annotate storageclass <name> storageclass.kubernetes.io/is-default-class="true"
     ```
3. **DNS & TLS**
   - Confirm a wildcard DNS entry exists: `*.apps.<cluster-domain>`.
   - If using custom certificates, ensure the ingress controller and your workstation trust the CA.
4. **Operator catalogs**
   - Confirm the `redhat-operators` source is available, or mirror it for disconnected installs.
   - For restricted networks, prepare ImageContentSourcePolicies and secrets ahead of time.

## 4. Clone the repo & export env vars

```bash
git clone https://github.com/<your-org>/gitops.git
cd gitops

export ENV=prod
export BASE_DOMAIN=apps.<cluster-domain>
export TARGET_REV=${TARGET_REV:-main}
export GIT_REPO_URL=${GIT_REPO_URL:-$(git remote get-url origin)}
```

- `BASE_DOMAIN` must match the wildcard DNS (e.g., `apps.ocp.prod.example`).
- `GIT_REPO_URL` should be your writable fork if Argo CD will push image updates.

## 5. Run the prod preflight

Use the accompanying script (added in this branch) to validate cluster prerequisites before bootstrapping.

```bash
./scripts/prod-preflight.sh
```

The preflight checks:
- `oc` login and API reachability.
- At least three Ready nodes (control plane) and two Ready worker nodes.
- Default storage class present.
- `BASE_DOMAIN` exported and wildcard DNS resolves.
- Operator catalog sources accessible.
- Reminder to review operator channels and secret management strategy.

Resolve any failures before continuing.

## 6. Bootstrap the GitOps stack (ENV=prod)

```bash
ENV=prod BASE_DOMAIN="$BASE_DOMAIN" TARGET_REV="$TARGET_REV" GIT_REPO_URL="$GIT_REPO_URL" \
  ./scripts/bootstrap.sh
```

What happens:
1. Installs (or ensures) OpenShift GitOps and OpenShift Pipelines via `charts/bootstrap-operators` in `openshift-operators`.
2. Waits for the default Argo CD instance in `openshift-gitops`.
3. Deploys the `bitiq-umbrella-by-env` ApplicationSet with `envFilter=prod` and `baseDomainOverride=$BASE_DOMAIN`.
4. Renders a single `bitiq-umbrella-prod` Application whose child Applications deploy in-cluster (`https://kubernetes.default.svc`) to the `bitiq-prod` namespace.

Monitor the Application:
```bash
oc -n openshift-gitops get application bitiq-umbrella-prod -w
```

After sync, confirm namespaces and routes:
```bash
oc get ns | grep bitiq-
oc -n bitiq-prod get routes
```

## 7. Configure production secrets & credentials

Production workloads must manage secrets via **External Secrets Operator (ESO) + Vault**. See [PROD-SECRETS](PROD-SECRETS.md) for details. High-level steps:

1. Run `scripts/bootstrap.sh` (step 6) — this now installs ESO (stable channel), waits for the CSV/CRDs, and deploys `charts/eso-vault-examples`.
2. Provision Vault access:
   - Enable Kubernetes auth, create the `gitops-prod` policy + role, and point it at the `vault-auth` ServiceAccount in `openshift-gitops`.
   - Populate the required KV paths under `gitops/data/...` (Argo CD token, Quay dockerconfig, GitHub webhook, toy-service config, toy-web config).
3. Verify that secrets reconcile:
   - If VSO/VCO is enabled for the env in the ApplicationSet values, the umbrella will deploy `vault-config-<env>` and `vault-runtime-<env>` and gate off the legacy ESO examples. See `docs/ESO-TO-VSO-MIGRATION.md` for cutover steps.
   - Otherwise, the legacy ESO example app will reconcile ExternalSecrets.
   
   Verify the target secrets exist:
   - `oc -n openshift-gitops get secret argocd-image-updater-secret`
   - `oc -n openshift-pipelines get secret quay-auth`
   - `oc -n openshift-pipelines get secret github-webhook-secret`
   - `oc -n bitiq-prod get secret toy-service-config`
   - `oc -n bitiq-prod get secret toy-web-config`
4. Link the generated registry secret to the Tekton `pipeline` ServiceAccount (`oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount`).
5. Rotate credentials directly in Vault; ESO refreshes the Kubernetes Secrets based on `refreshInterval`.

Emergency-only fallback: if Vault or ESO is unavailable, halt deployments instead of dropping to ad-hoc `oc create secret` flows. Document the incident and restore the GitOps path before resuming deploys.

Note (private registries): if your registries are private, configure an image pull secret for Image Updater and set `imageUpdater.pullSecret` in the umbrella chart values (refer to charts/bitiq-umbrella/values-common.yaml:16) or manage it via ESO with a separate ExternalSecret in `openshift-gitops`.

## 7. Configure secrets & credentials (Vault operators)

Production now uses VSO/VCO by default. The umbrella renders `vault-config-prod` (VCO) and `vault-runtime-prod` (VSO). Review values in `charts/argocd-apps/values.yaml` under the `prod` block — addresses and role/policy names should match your Vault deployment.

1) Verify Applications:

```bash
oc -n openshift-gitops get application vault-config-prod vault-runtime-prod
```

2) Seed Vault (no `oc create secret`):

```bash
# Argo CD Image Updater token
vault kv put gitops/data/argocd/image-updater token="$ARGOCD_TOKEN"

# Quay dockerconfigjson for Tekton pipeline SA
vault kv put gitops/data/registry/quay dockerconfigjson='{"auths":{"quay.io":{"auth":"<base64 user:token>"}}}'

# GitHub webhook secret used by Tekton triggers
vault kv put gitops/data/github/webhook token='<random-string>'

# Optional runtime configs for sample apps
vault kv put gitops/data/services/toy-service/config FAKE_SECRET='<value>'
vault kv put gitops/data/services/toy-web/config API_BASE_URL='https://svc-api.apps.<cluster-domain>'
```

3) Link Quay secret to the Tekton SA (idempotent):

```bash
oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount
```

4) Ensure Argo CD has write-enabled repo credentials (PAT/SSH) for Image Updater write-back.

## 8. Argo CD RBAC & SSO hardening

Strengthen access to the `openshift-gitops` Argo CD instance before granting production access.

### 8.1 Create OpenShift groups

Define admin and read-only groups mapped to Argo CD roles:

```bash
oc adm groups new argocd-admins
oc adm groups new argocd-viewers

# Add platform admins to argocd-admins; add delivery team users to argocd-viewers
oc adm groups add-users argocd-admins <admin-user-1> <admin-user-2>
oc adm groups add-users argocd-viewers <viewer-user-1> <viewer-user-2>
```

### 8.2 Patch the Argo CD CR

Apply RBAC policy and enable the dedicated `argocd-image-updater` account:

```bash
cat <<'YAML' | oc apply -n openshift-gitops -f -
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
spec:
  rbac:
    policy: |
      g, argocd-admins, role:admin
      g, argocd-viewers, role:readonly
      g, system:cluster-admins, role:admin
      p, role:readonly, applications, get, */*, allow
      p, role:readonly, applications, sync, */*, deny
    scopes: '[groups,sub,preferred_username,email]'
  extraConfig:
    accounts.argocd-image-updater: apiKey
    admin.enabled: "false"
YAML
```

Notes:

- `admin.enabled: false` disables the legacy local `admin` user.
- `role:readonly` grants dashboard visibility without sync permissions. Adjust policies to match your org’s needs.
- Keeping `system:cluster-admins` mapped to `role:admin` ensures cluster-admins retain emergency access.

### 8.3 Configure automation tokens

- Generate API tokens for automation:

  ```bash
  argocd login $(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}') \
    --sso --grpc-web
  argocd account generate-token --account argocd-image-updater --grpc-web
  ```

- Never share human SSO tokens with automation; prefer dedicated Argo CD accounts scoped by policy.

### 8.4 Audit and monitor

- Use `oc -n openshift-gitops get application` to verify permissions (admins can sync, viewers cannot).
- Enable Argo CD audit logging (`spec.controller.metrics.enabled: true`) if not already configured.
- Periodically review group membership and rotate Image Updater tokens.

## 9. Tekton hardening (prod)

Tekton pipelines run in the `openshift-pipelines` namespace by default. Apply the following guardrails before granting production access.

### 9.1 ServiceAccount and permissions

- Keep the default `pipeline` ServiceAccount but scope permissions to the namespaces it needs:

  ```bash
  oc policy add-role-to-user system:image-pusher \
    system:serviceaccount:openshift-pipelines:pipeline -n bitiq-prod
  oc policy add-role-to-user edit \
    system:serviceaccount:openshift-pipelines:pipeline -n bitiq-prod
  ```

- Avoid granting `cluster-admin` or broad roles. If multiple app namespaces exist, grant namespace-scoped roles explicitly.

### 9.2 Secrets and image pulls

- Use VSO/Vault (see [PROD-SECRETS](PROD-SECRETS.md)) to materialize registry and webhook secrets.
- Link the Quay secret to the ServiceAccount for both pull and mount usage:

  ```bash
  oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount
  ```

- If building to the internal registry, replace Quay-specific annotations with `image-registry.openshift-image-registry.svc:5000` and grant `system:image-builder` as needed.

### 9.3 Resource quotas and runtimes

- Set namespace limits to prevent noisy-neighbor issues:

  ```bash
  oc -n openshift-pipelines apply -f - <<'YAML'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tekton-build-quota
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 32Gi
    limits.cpu: "16"
    limits.memory: 64Gi
    persistentvolumeclaims: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: tekton-defaults
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: 250m
      memory: 512Mi
    default:
      cpu: 2
      memory: 4Gi
YAML
```

- Tailor the values to your cluster capacity. Use separate quotas per namespace if you isolate pipelines.

### 9.4 TektonConfig tuning

- Confirm the cluster-wide `TektonConfig` (installed by the operator) has reasonable defaults:
  - `spec.pipeline.metrics.pipelinerun.duration-type: histogram`
  - `spec.pipeline.default-timeout-minutes`: e.g., `60`
  - `spec.chain`: disable if not using Tekton Chains.
- Apply overrides via `oc patch tektonconfig config --type merge -p '{...}'` as needed.

### 9.5 Observability and retention

- Enable log retention by forwarding Tekton namespaces to your logging stack or OpenShift Logging.
- Use `tkn pipelinerun list -n openshift-pipelines` regularly to spot lingering runs.
- Consider pruning old PipelineRuns: `tkn pipelinerun delete --keep 20 -n openshift-pipelines` (script as a CronJob if policy allows).

### 9.6 Build tools and images

- Validate that container images used for builds (Go, NodeJS, Buildah) come from trusted registries.
- Mirror images to an internal registry for disconnected clusters and update `charts/ci-pipelines/values.yaml` accordingly.
- Where possible, enforce signed images and supply chain policies (e.g., Tekton Chains, Sigstore) in future iterations.

## 10. Validate the deployment

1. **Local chart validation**
   ```bash
   make lint
   make template
   make validate
   ```

2. **Cluster smoke tests**
   ```bash
   make smoke ENV=prod BASE_DOMAIN="$BASE_DOMAIN"
   ```
   - Optionally run `./scripts/smoke-image-update.sh` to tail Image Updater logs.

3. **Tekton pipelines**
   - Push a code or tag change to the sample repositories (`toy-service`, `toy-web`).
   - Verify PipelineRuns succeed:
     ```bash
     oc -n openshift-pipelines get pipelineruns -w
     ```
   - Confirm new image tags reach the `bitiq-prod` namespace and the sample app Routes serve updated content.

4. **Image Updater**
   ```bash
   oc -n openshift-gitops logs deploy/argocd-image-updater --since=10m | grep -E 'Committing|Pushed change'
   ```
  - Ensure commits land in `charts/toy-service/values-prod.yaml` and `charts/toy-web/values-prod.yaml` on the tracked branch.

## 11. Advanced: Central Argo CD (documentation only)

If you later choose to manage prod from a central Argo CD instance:
- Register the prod cluster with `argocd cluster add` and store credentials securely (consider ESO/SealedSecrets).
- Update `charts/argocd-apps/values.yaml` to set `prod.clusterServer` to the external API URL.
- Parameterize nested Application destinations to target the remote cluster, and ensure the control cluster hosts all CRDs (Application, ApplicationSet).
- Plan for HA and capacity: increase repo-server and application-controller resources, and monitor sync concurrency.
- Revisit network policies to allow outbound gRPC/HTTPS from the central cluster to prod.

No chart changes for central Argo are included in this branch; treat this section as future guidance only.

## 12. Operations & troubleshooting
- **Namespace or permission errors**: Confirm Argo CD has permission in `bitiq-prod` and `openshift-pipelines` (cluster-admin handles this by default).
- **Routes unreachable**: Check ingress controller status, wildcard DNS, and firewall rules.
- **Pipeline image pushes fail**: Validate registry credentials and that the service account has the `system:image-pusher` role for the target namespace.
- **Image Updater push errors**: Ensure Git credentials have write access and that the token is not expired.
- **Operator upgrades**: Coordinate GitOps/Pipelines operator channel bumps; test in staging first.
- **Disaster recovery**: Follow `docs/ROLLBACK.md` for Git-driven rollbacks; avoid manual cluster edits.

## 13. References (September 2025)

- OCP 4.19 docs: https://docs.redhat.com/en/documentation/openshift_container_platform/4.19
- OpenShift GitOps documentation: https://docs.openshift.com/gitops/latest/
- OpenShift Pipelines 1.17 docs: https://docs.openshift.com/pipelines/1.17/
- Argo CD Image Updater: https://argocd-image-updater.readthedocs.io/en/stable/
- SealedSecrets: https://sealed-secrets.netlify.app/
- External Secrets Operator: https://external-secrets.io/latest/
