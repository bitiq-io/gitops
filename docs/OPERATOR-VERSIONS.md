# Operator Version Matrix

Source of truth for the operator versions we target on OpenShift 4.19 clusters. Use this matrix when following upstream docs, pinning subscriptions, or preparing upgrades. Update it as part of any operator bump PR (see T12/T18 guardrails in `docs/GITOPS-IMPROVEMENT-PLAN.md`).

| Component | Operator Package | CatalogSource (`source`) | Install Namespace | Channel | Starting CSV / Version | Upstream Docs |
|-----------|------------------|--------------------------|------------------|---------|------------------------|---------------|
| OpenShift GitOps | `openshift-gitops-operator` | `redhat-operators` | `openshift-operators` | `gitops-1.18` | `openshift-gitops-operator.v1.18.0` | https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18 |
| OpenShift Pipelines | `openshift-pipelines-operator-rh` | `redhat-operators` | `openshift-operators` | `pipelines-1.20` | `openshift-pipelines-operator-rh.v1.20.0` | https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20 |
| Vault Secrets Operator (VSO) | `vault-secrets-operator` | `certified-operators` (verify availability in your catalog; fallback to `community-operators` if needed) | `hashicorp-vault-secrets-operator` | `stable` | `vault-secrets-operator.v1.0.1` | https://developer.hashicorp.com/vault/docs/platform/k8s/vso |
| Vault Config Operator (VCO) | `vault-config-operator` | `community-operators` | `vault-config-operator` | `alpha` | `vault-config-operator.v0.8.34` | https://github.com/redhat-cop/vault-config-operator |
| Couchbase Autonomous Operator (CAO) | `couchbase-operator-certified` | `certified-operators` | `openshift-operators` | `stable` | `<verify in cluster>` | https://docs.couchbase.com/operator/current/overview.html |

## Verification Commands

After bootstrap or an upgrade, confirm expected versions are installed:

```bash
oc get csv -n openshift-operators --selector=operators.coreos.com/openshift-gitops-operator.openshift-operators
oc get csv -n openshift-operators --selector=operators.coreos.com/openshift-pipelines-operator-rh.openshift-operators
oc get csv -n hashicorp-vault-secrets-operator --selector=operators.coreos.com/vault-secrets-operator.vault-secrets-operator
oc get csv -n vault-config-operator --selector=operators.coreos.com/vault-config-operator.vault-config-operator
oc get csv -n openshift-operators --selector=operators.coreos.com/couchbase-operator-certified.openshift-operators
```

Replace namespaces if you deploy the operators somewhere other than their defaults. Record any deviations from this matrix in the PR description and update the table before merging.
