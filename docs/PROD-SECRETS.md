# Production Secrets with External Secrets Operator (ESO) + Vault

This guide describes how to manage production secrets for the `gitops` stack using [External Secrets Operator (ESO)](https://external-secrets.io/) with HashiCorp Vault as the backend. It focuses on the credentials managed by default by this repo:

1. **Argo CD Image Updater token** (`openshift-gitops/argocd-image-updater-secret`)
2. **Container registry credentials** for the Tekton `pipeline` ServiceAccount (`openshift-pipelines/quay-auth`)
3. **GitHub webhook secret** (`openshift-pipelines/github-webhook-secret`)
4. **toy-service runtime config** (`bitiq-<env>/toy-service-config`)
5. **toy-web runtime config** (`bitiq-<env>/toy-web-config`)

The repository ships a Helm chart (`charts/eso-vault-examples`) that renders a Vault `ClusterSecretStore` and the ExternalSecrets for these credentials. The chart is installed automatically by `scripts/bootstrap.sh` once ESO is ready; override the values only when you need to point at a different Vault or adjust secret paths.

## 1. Prerequisites

- OCP 4.19 cluster with cluster-admin access.
- HashiCorp Vault (Open Source or Enterprise) reachable from the cluster.
- External Secrets Operator (ESO) 0.9+ installed in the cluster.
- Git repository access for the Helm chart (`gitops` repo) and CI/CD components.
- Vault authentication configured for Kubernetes (recommended) or AppRole.

### 1.1 Install External Secrets Operator

`scripts/bootstrap.sh` automatically installs ESO (stable channel) and waits for the CSV/CRDs. The steps below are kept for reference if you need to install manually or recover from a failed upgrade.

Use OperatorHub in the OpenShift web console or apply the operator manifests via CLI:

```bash
# Create the operator namespace and subscription
oc new-project external-secrets-operator || true
cat <<'YAML' | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: external-secrets-operator
  namespace: external-secrets-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: external-secrets-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
YAML

# Wait for the operator to become ready
oc get csv -n external-secrets-operator -w
```

ESO installs cluster-scoped CRDs such as `ClusterSecretStore` and `ExternalSecret`.

Note: The example uses the `stable` channel with `installPlanApproval: Automatic`. For production, review your organization’s operator lifecycle policy — you may prefer `Manual` approvals to control upgrades and coordinate with change windows. Pinning or mirroring catalog sources may also be required in regulated or disconnected environments.

#### 1.1.1 Create Kubernetes ServiceAccount for Vault auth

The example `ClusterSecretStore` references a ServiceAccount that Vault uses to validate projected tokens during Kubernetes auth. Create it in the namespace you plan to reference (defaults to `openshift-gitops/vault-auth` in this repo’s values):

```bash
oc -n openshift-gitops create sa vault-auth || true
```

Notes:
- This ServiceAccount is only used for Vault authentication. It does not need cluster-wide permissions or access to Argo CD resources.
- If you choose a different namespace/name, update `secretStore.provider.vault.auth.serviceAccountRef` accordingly in the chart values.

### 1.2 Create a Vault Policy and Role

Enable the Kubernetes auth method in Vault (if not already configured):

```bash
vault auth enable kubernetes || true
vault write auth/kubernetes/config \
  token_reviewer_jwt="$(oc whoami -t)" \
  kubernetes_host="$(oc whoami --show-server)" \
  kubernetes_ca_cert="$(oc get configmap -n openshift-config-managed kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')"
```

Create a Vault policy granting read access to the paths that will store secrets managed by ESO:

```bash
cat <<'HCL' | vault policy write gitops-prod -
path "gitops/data/*" {
  capabilities = ["read"]
}
HCL
```

Create a Vault role that ties the policy to a Kubernetes ServiceAccount:

```bash
vault write auth/kubernetes/role/gitops-prod \
  bound_service_account_names="vault-auth" \
  bound_service_account_namespaces="openshift-gitops" \
  policies="gitops-prod" \
  ttl="1h"
```

> Adjust the namespace/name if you prefer to host the ServiceAccount elsewhere. The Helm chart defaults to `openshift-gitops/vault-auth`.

### 1.3 Populate Vault Secrets

Store the required secrets under the agreed Vault paths (`gitops/data/...`). Examples:

```bash
# Argo CD Image Updater token
vault kv put gitops/data/argocd/image-updater token="<ARGOCD_TOKEN>"

# Quay dockerconfigjson
vault kv put gitops/data/registry/quay dockerconfigjson="$(cat dockercfg.json | base64 -w0)"

# GitHub webhook secret
vault kv put gitops/data/github/webhook token="<RANDOM_WEBHOOK_SECRET>"

# toy-service runtime config (optional)
vault kv put gitops/data/services/toy-service/config fake_secret="<DEMO_FAKE_SECRET>"
```

Use the same keys (`token`, `dockerconfigjson`) that the Helm chart references.

## 2. Deploy ESO + Vault resources via Helm

The `eso-vault-examples` chart renders:

- `ClusterSecretStore` (`vault-global`) configured for Vault + Kubernetes auth.
- `ExternalSecret` resources for the Argo CD token, Quay credentials, GitHub webhook secret, toy-service config, and toy-web config.

### 2.1 Review and customize values

Bootstrap installs the chart with the repository defaults. If you need to customize it (e.g., point to a different Vault endpoint, adjust namespaces, or tweak refresh intervals), copy the values and edit them before re-applying:

```bash
cat charts/eso-vault-examples/values.yaml > /tmp/eso-values.yaml
$EDITOR /tmp/eso-values.yaml
```

Key fields to review/override:

- `secretStore.provider.vault.server`: Vault HTTPS endpoint.
- `secretStore.provider.vault.auth.role`: Vault role created in section 1.2.
- `secretStore.provider.vault.auth.serviceAccountRef`: ServiceAccount that ESO will impersonate.
- `argocdToken/quayCredentials/webhookSecret.data[].remoteRef.key`: Vault KV paths.
- `toyServiceConfig.data[].remoteRef.key`: Vault KV path for backend runtime secrets (`fake_secret` by default).
- `toyWebConfig.data[].remoteRef.key`: Vault KV path for frontend runtime secrets (`api_base_url` by default).
- `quayCredentials.secretType`: defaults to `kubernetes.io/dockerconfigjson` to ensure Tekton interprets the secret correctly.

Vault KV paths expected by the defaults:

- `gitops/data/argocd/image-updater` → `token`
- `gitops/data/registry/quay` → `dockerconfigjson`
- `gitops/data/github/webhook` → `token`
- `gitops/data/services/toy-service/config` → `fake_secret`
- `gitops/data/services/toy-web/config` → `api_base_url`

Optional (Tekton credential helper): annotate the generated Quay secret so Tekton auto-detects it for `https://quay.io`.

```yaml
quayCredentials:
  enabled: true
  annotations:
    tekton.dev/docker-0: https://quay.io
```

### 2.2 Install the chart

```bash
helm upgrade --install eso-vault-examples charts/eso-vault-examples \
  --namespace external-secrets-operator \
  --create-namespace \
  --values /tmp/eso-values.yaml
```

This deploys/updates the `ClusterSecretStore` and ExternalSecrets. ESO will reconcile the target secrets in their respective namespaces.

Verify that the secrets materialize:

```bash
oc -n openshift-gitops get secret argocd-image-updater-secret
oc -n openshift-pipelines get secret quay-auth
oc -n openshift-pipelines get secret github-webhook-secret
oc -n bitiq-local get secret toy-service-config
oc -n bitiq-local get secret toy-web-config
```

### 2.3 Validate manifests locally

Run kubeconform against the rendered manifests to ensure the CRDs and ExternalSecrets validate cleanly:

```bash
helm template charts/eso-vault-examples \
  --set enabled=true \
  --set secretStore.enabled=true \
  --set argocdToken.enabled=true \
  --set quayCredentials.enabled=true \
  --set webhookSecret.enabled=true \
  | kubeconform -strict -ignore-missing-schemas
```

> `kubeconform` will ignore ESO CRDs by default due to `-ignore-missing-schemas`. The command still verifies structural correctness and required fields like `secretStoreRef`, `refreshInterval`, and Vault references.

### 2.4 Link ServiceAccounts (Tekton + Argo)

For Tekton pipelines, ensure the `pipeline` ServiceAccount mounts the registry secret:

```bash
oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount
```

For Argo CD Image Updater, ESO writes the token to the expected secret; no additional linking is necessary.

### 2.5 Local developer shortcut (`make dev-vault`)

For CRC/local parity testing, run:

```bash
make dev-vault
```

This target:

1. Deploys a dev-mode Vault (`vault-dev` namespace) with the default root token.
2. Enables Kubernetes auth, creates the `gitops-prod` policy + role, and seeds sample credentials under `gitops/data/...`.
3. Ensures `vault-auth` exists in `openshift-gitops`.
4. Installs/refreshes the `eso-vault-examples` Helm release with overrides pointing to the dev Vault.
5. Waits for the ESO Subscription to reconcile and for CRDs to register.

Run `make dev-vault-down` to remove the dev Vault and uninstall the chart.

## 3. Operational considerations

- **Secret rotation**: Rotate credentials in Vault; ESO refreshes on the `refreshInterval` defined for each ExternalSecret (e.g., Argo token every minute).
- **Access control**: Limit Vault policies to read-only access for the required paths. Use Vault audit logs to track access.
- **ServiceAccount tokens**: Use short-lived projected tokens for the `vault-auth` ServiceAccount (OCP creates them automatically when ESO requests them).
- **Monitoring**: ESO publishes metrics via the `external-secrets-operator` namespace (`ServiceMonitor` available if using OpenShift Monitoring or Prometheus Operator).
- **Disaster recovery**: Secrets are sourced from Vault; ensure Vault backups capture the paths used here. Re-running the Helm chart redeploys the ExternalSecrets.

## 4. Extending to other secrets

To add more secrets:

1. Create a new block in `values.yaml` mirroring the existing examples (set `enabled: true`, update `remoteRef` keys).
2. Add a template include referencing the new block (see `templates/externalsecret-*.yaml`).
3. Populate the corresponding path in Vault with key/value pairs.

Alternatively, manage additional ExternalSecrets outside of this chart—ensure they reference the same `ClusterSecretStore` or another store as required.

## 5. References

- ESO documentation: https://external-secrets.io/latest/
- Vault Kubernetes auth: https://developer.hashicorp.com/vault/docs/auth/kubernetes
- OpenShift GitOps 1.18 release notes: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/release_notes/
- OpenShift Pipelines 1.20 release notes: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20/html/release_notes/
