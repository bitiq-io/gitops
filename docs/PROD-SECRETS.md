# Production Secrets — Vault via VSO/VCO

HashiCorp Vault Secrets Operator (VSO) and Vault Config Operator (VCO) are now the authoritative path for managing platform credentials across environments. The umbrella chart renders the appropriate Argo CD Applications (`vault-config-<env>`, `vault-runtime-<env>`) when `vault.*` flags are enabled per environment in `charts/argocd-apps/values.yaml`. External Secrets Operator (ESO) remains available only as a legacy fallback (see the appendix).

## 1. Prerequisites

- OpenShift 4.19 cluster with cluster-admin access.
- HashiCorp Vault (OSS or Enterprise) reachable from the cluster (in-cluster Service or external endpoint).
- Bootstrap installed the pinned operators (GitOps 1.18, Pipelines 1.20, VSO 1.0.1, VCO 0.8.34) — see `docs/OPERATOR-VERSIONS.md`.
- For each environment, configure the Vault address, Kubernetes auth mount, and role names in `charts/argocd-apps/values.yaml` before syncing:

  ```yaml
  - name: local
    vaultRuntimeEnabled: true
    vaultRuntimeAddress: http://vault-dev.vault-dev.svc:8200
    vaultConfigEnabled: true
    vaultConfigAddress: http://vault-dev.vault-dev.svc:8200
    # … additional mounts/role names …

  - name: sno
    vaultRuntimeEnabled: true
    vaultRuntimeAddress: https://vault-sno.vault.svc:8200      # replace with your Vault endpoint
    vaultConfigEnabled: true
    vaultConfigAddress: https://vault-sno.vault.svc:8200
    vaultRuntimeRoleName: gitops-sno
    vaultConfigRoleName: gitops-sno
    vaultConfigPolicyName: gitops-sno
  ```

  Adjust the addresses, role, and policy names to match your Vault deployment. Leave `vaultRuntimeEnabled`/`vaultConfigEnabled` set to `false` for environments that still depend on ESO (e.g. production during phased migration).

## 2. Configure Vault operators per environment

### 2.1 Control plane (VCO)

The `vault-config-<env>` Application renders the VCO chart (`charts/vault-config`) with the parameters above. On successful sync, Vault will contain:

- `AuthEngineMount` and `KubernetesAuthEngineConfig` for the configured mount (`vault.config.mountPath`, default `kubernetes`).
- `Policy` (name `vault.config.policyName`) granting read/list access to `gitops/data/*`.
- `KubernetesAuthEngineRole` (name `vault.config.roleName`) bound to the `default` ServiceAccount in `openshift-gitops`, `openshift-pipelines`, and `bitiq-<env>`.

**Checklist**

```bash
oc -n openshift-gitops get application vault-config-<env>
oc get kubernetesauthengineconfigs.secrets.hashicorp.com --all-namespaces
vault read auth/<mount>/role/<role>    # optional verification from Vault CLI
```

If you need tighter scopes, override `policies[]` or `roles[].targetNamespaces/targetServiceAccounts` in the chart values (or via Application parameters) before syncing.

### 2.2 Runtime secrets (VSO)

The `vault-runtime-<env>` Application renders the VSO chart (`charts/vault-runtime`). It creates per-namespace `VaultConnection` + `VaultAuth` resources and a `VaultStaticSecret` for each managed credential:

| Vault path | Destination Secret | Namespace | Notes |
| --- | --- | --- | --- |
| `gitops/data/argocd/image-updater` | `argocd-image-updater-secret` | `openshift-gitops` | Used by Argo CD Image Updater (API token). |
| `gitops/data/registry/quay` | `quay-auth` (`kubernetes.io/dockerconfigjson`) | `openshift-pipelines` | Mounted by Tekton pipeline SA and Image Updater. |
| `gitops/data/github/webhook` | `github-webhook-secret` | `openshift-pipelines` | Consumed by Tekton EventListener (GitHub interceptor). |
| `gitops/data/services/toy-service/config` | `toy-service-config` | `bitiq-<env>` | Includes `rolloutRestartTargets` so pods restart on Secret changes. |
| `gitops/data/services/toy-web/config` | `toy-web-config` | `bitiq-<env>` | Example runtime config for the frontend. |

**Checklist**

```bash
oc -n openshift-gitops get application vault-runtime-<env>
oc -n openshift-gitops get vaultstaticsecrets.secrets.hashicorp.com
oc -n bitiq-<env> get secrets toy-service-config toy-web-config
```

If you add new services, extend `charts/vault-runtime/values.yaml` (or override via the Application) with additional `VaultStaticSecret` definitions.

## 3. Seed Vault data (per environment)

Populate Vault with the required keys — this replaces all `oc create secret` flows:

```bash
# Argo CD Image Updater service account token (write-enabled repo access required)
vault kv put gitops/data/argocd/image-updater token="$ARGOCD_TOKEN"

# Quay (or other registry) credentials as dockerconfigjson
vault kv put gitops/data/registry/quay dockerconfigjson='{"auths":{"quay.io":{"auth":"<base64 user:token>"}}}'

# GitHub webhook secret used by Tekton triggers
vault kv put gitops/data/github/webhook token='<random-string>'

# Optional runtime overrides for sample apps
vault kv put gitops/data/services/toy-service/config FAKE_SECRET='<value>'
vault kv put gitops/data/services/toy-web/config API_BASE_URL='https://svc-api.apps.<cluster-domain>'
```

For local development, `make dev-vault` provisions a dev-mode Vault, seeds demo values, and renders the same VCO/VSO resources with `VAULT_OPERATORS=true`.

## 4. Verification checklist

1. Argo CD Applications are `Synced/Healthy`:
   ```bash
   oc -n openshift-gitops get application vault-config-<env> vault-runtime-<env>
   ```
2. VCO resources exist:
   ```bash
   oc get kubernetesauthengineconfigs.redhatcop.redhat.io --all-namespaces
   oc get kubernetesauthengineroles.redhatcop.redhat.io --all-namespaces
   ```
3. VSO reconciles secrets:
   ```bash
   oc -n openshift-pipelines get secrets quay-auth github-webhook-secret
   oc -n openshift-gitops get secrets argocd-image-updater-secret
   oc -n bitiq-<env> get secrets toy-service-config toy-web-config
   ```
4. Image Updater can authenticate and perform write-back (check logs or use `scripts/e2e-updater-smoke.sh`).
5. Tekton pipelines can pull/push images — ensure `quay-auth` is linked to the `pipeline` ServiceAccount:
   ```bash
   oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount
   ```

## 5. Operations & rotation

- To rotate any credential, write the new value to the same Vault path; VSO reconciles the Secret and (for toy-service) triggers a rollout via `rolloutRestartTargets`.
- Never patch Kubernetes Secrets directly — treat Vault as the source of truth.
- Keep Vault audit logs enabled and scope policies per environment (e.g., `gitops-local`, `gitops-sno`).
- When introducing new services, add the Vault path + `VaultStaticSecret` entry, seed Vault, and sync the umbrella chart.

## Appendix A — Legacy ESO flow (deprecated)

The repository retains `charts/eso-vault-examples/` for environments that still rely on External Secrets Operator. To continue using ESO temporarily:

1. Set `vaultRuntimeEnabled=false` and `vaultConfigEnabled=false` for the environment in `charts/argocd-apps/values.yaml`.
2. Sync the umbrella chart; Argo CD will render `eso-vault-examples-<env>` instead of the VSO/VCO Applications.
3. Follow the migration guide (`docs/ESO-TO-VSO-MIGRATION.md`) to map each `ExternalSecret` to its VSO/VCO equivalent and plan the cutover.

> Dual-writer protection: `policy/gitops/no_dual_secret_operators.rego` blocks manifests that render both ESO and VSO for the same environment. Flip the env flags in Git before switching operators.
