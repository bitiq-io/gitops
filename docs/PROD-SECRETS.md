# Production Secrets with External Secrets Operator (ESO) + Vault

This guide describes how to manage production secrets for the `gitops` stack using [External Secrets Operator (ESO)](https://external-secrets.io/) with HashiCorp Vault as the backend. It focuses on the three credentials required by the repo:

1. **Argo CD Image Updater token** (`openshift-gitops/argocd-image-updater-secret`)
2. **Container registry credentials** for the Tekton `pipeline` ServiceAccount (`openshift-pipelines/quay-auth`)
3. **GitHub webhook secret** (`openshift-pipelines/github-webhook-secret`)

The repository ships an optional Helm chart (`charts/eso-vault-examples`) that renders a Vault `ClusterSecretStore` and `ExternalSecret` resources for these credentials. By default, the chart is disabled so that production operators can enable and customize it deliberately.

## 1. Prerequisites

- OCP 4.19 cluster with cluster-admin access.
- HashiCorp Vault (Open Source or Enterprise) reachable from the cluster.
- External Secrets Operator (ESO) 0.9+ installed in the cluster.
- Git repository access for the Helm chart (`gitops` repo) and CI/CD components.
- Vault authentication configured for Kubernetes (recommended) or AppRole.

### 1.1 Install External Secrets Operator

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
```

Use the same keys (`token`, `dockerconfigjson`) that the Helm chart references.

## 2. Deploy ESO + Vault resources via Helm

The `eso-vault-examples` chart is optional and disabled by default. It renders:

- `ClusterSecretStore` (`vault-global`) configured for Vault + Kubernetes auth.
- `ExternalSecret` resources for the Argo CD token, Quay credentials, and GitHub webhook secret.

### 2.1 Review and customize values

Copy the chart values and edit them to match your Vault deployment:

```bash
cat charts/eso-vault-examples/values.yaml > /tmp/eso-values.yaml
$EDITOR /tmp/eso-values.yaml
```

Key fields to review:

- `secretStore.provider.vault.server`: Vault HTTPS endpoint.
- `secretStore.provider.vault.auth.role`: Vault role created in section 1.2.
- `secretStore.provider.vault.auth.serviceAccountRef`: ServiceAccount that ESO will impersonate.
- `argocdToken/quayCredentials/webhookSecret.data[].remoteRef.key`: Vault KV paths.
- `quayCredentials.secretType`: defaults to `kubernetes.io/dockerconfigjson` to ensure Tekton interprets the secret correctly.

### 2.2 Install the chart

Enable the chart and desired secrets by setting `enabled=true` and toggling individual blocks:

```bash
helm upgrade --install eso-vault-examples charts/eso-vault-examples \
  --namespace external-secrets-operator \
  --create-namespace \
  --values /tmp/eso-values.yaml \
  --set enabled=true \
  --set secretStore.enabled=true \
  --set argocdToken.enabled=true \
  --set quayCredentials.enabled=true \
  --set webhookSecret.enabled=true
```

This deploys the `ClusterSecretStore` and ExternalSecrets. ESO will reconcile the target secrets in their respective namespaces.

Verify that the secrets materialize:

```bash
oc -n openshift-gitops get secret argocd-image-updater-secret
oc -n openshift-pipelines get secret quay-auth
oc -n openshift-pipelines get secret github-webhook-secret
```

### 2.3 Link ServiceAccounts (Tekton + Argo)

For Tekton pipelines, ensure the `pipeline` ServiceAccount mounts the registry secret:

```bash
oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount
```

For Argo CD Image Updater, ESO writes the token to the expected secret; no additional linking is necessary.

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
