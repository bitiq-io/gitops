# ESO → VSO/VCO Migration Guide

This guide maps existing ESO resources to their VSO/VCO equivalents and outlines the cutover flow per secret, per environment. Use this when migrating from External Secrets Operator (ESO) to HashiCorp Vault Secrets Operator (VSO) and Vault Config Operator (VCO).

## Resource Mapping

- ClusterSecretStore (ESO) → VaultConnection (VSO) + VaultAuth (VSO)
  - Cluster-scoped Vault connection and auth settings become per-namespace VSO `VaultConnection` and `VaultAuth` resources.
  - VCO handles Vault control-plane setup (auth mount/config/roles); VSO consumes the resulting mount/role.

- ExternalSecret (ESO) → VaultStaticSecret (VSO) or VaultDynamicSecret (VSO)
  - KV v2 paths map to `VaultStaticSecret.spec.{mount: kv, type: kv-v2, path: <kv path>}`
  - Destination Secret name remains the same to avoid app changes.
  - For dockerconfigjson: use `destination.type: kubernetes.io/dockerconfigjson` with a `.dockerconfigjson` template in `destination.transformation.templates`.

## Per‑secret migrations (platform)

- openshift-gitops/argocd-image-updater-secret
  - ESO → VSO: `VaultStaticSecret` in `openshift-gitops` with `path: gitops/data/argocd/image-updater`, type `Opaque`.

- openshift-pipelines/quay-auth
  - ESO → VSO: `VaultStaticSecret` in `openshift-pipelines`, `path: gitops/data/registry/quay`, type `kubernetes.io/dockerconfigjson`, template `.dockerconfigjson` from the `dockerconfigjson` key.

- openshift-pipelines/github-webhook-secret
  - ESO → VSO: `VaultStaticSecret` in `openshift-pipelines`, `path: gitops/data/github/webhook`, type `Opaque`.

## Per‑app migrations

- bitiq-<env>/toy-service-config
  - ESO → VSO: `VaultStaticSecret` in `bitiq-<env>`, `path: gitops/data/services/toy-service/config`.

- bitiq-<env>/toy-web-config
  - ESO → VSO: `VaultStaticSecret` in `bitiq-<env>`, `path: gitops/data/services/toy-web/config`.

## Cutover Flow (per env)

1) Prepare Vault config (VCO)
   - Ensure `AuthEngineMount` and `KubernetesAuthEngineConfig` exist (mount: `kubernetes`).
   - Create `KubernetesAuthEngineRole` with the policy for required paths.

2) Create VSO connection/auth
   - One `VaultConnection` per namespace; one `VaultAuth` per namespace using the mount/role.

3) Create VSO secrets
   - Add `VaultStaticSecret`/`VaultDynamicSecret` for each ESO `ExternalSecret`.
   - Keep destination Secret names identical.

4) Gate off ESO
   - In the umbrella, set `vault.runtime.enabled=true` for the env to suppress `eso-vault-examples` and deploy `vault-runtime`/`vault-config` Applications.
   - Verify VSO has reconciled destination Secrets; check pod env/volume mounts.

5) Verify and clean up
   - Confirm Argo Application is Healthy/Synced and the workloads use updated Secrets.
   - Remove the ESO chart and any remaining `ExternalSecret`/`ClusterSecretStore` resources for that env.

## Local (ENV=local) quick path

- Option A (umbrella): set `vault.runtime.enabled=true` and `vault.config.enabled=true` with local dev Vault address.
- Option B (helper): run `VAULT_OPERATORS=true make dev-vault` to install VSO runtime chart pointed at the dev Vault.

## Notes

- Do not run ESO and VSO against the same destination Secret concurrently.
- Keep Secret names stable to avoid app changes.
- For rotation-triggered pod reloads, choose either checksum annotations or a reloader operator (see T16 in the improvement plan).
