# Platform & Tool Version Matrix

Source of truth for the versions we target across the CRC-based environment. Keep this table current any time we upgrade CRC/OpenShift, operators, or workload components. When bumping a version, update the table **and** include a link to the matching upstream documentation so everyone lands on the correct manual/reference set for that specific release.

## Platform Baseline

| Component | Version | Verification | Documentation |
|-----------|---------|--------------|---------------|
| Red Hat OpenShift Local (CRC) | `2.53.0+a6f712` | `crc version` | https://access.redhat.com/documentation/en-us/red_hat_openshift_local/2.53 |
| OpenShift Container Platform (cluster) | `4.19.3` | `oc version` (Server) | https://docs.openshift.com/container-platform/4.19/ |

## Operators (GitOps-managed)

| Component | Package / Source | Channel / Notes | Version (CSV / Chart) | Verification | Documentation |
|-----------|------------------|-----------------|-----------------------|--------------|---------------|
| OpenShift GitOps | `openshift-gitops-operator` (Red Hat) | `gitops-1.18` | `openshift-gitops-operator.v1.18.1` | `oc get csv -n openshift-operators --selector=operators.coreos.com/openshift-gitops-operator.openshift-operators` | https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18 |
| OpenShift Pipelines | `openshift-pipelines-operator-rh` (Red Hat) | `pipelines-1.20` | `openshift-pipelines-operator-rh.v1.20.0` | `oc get csv -n openshift-operators --selector=operators.coreos.com/openshift-pipelines-operator-rh.openshift-operators` | https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20 |
| Vault Secrets Operator (VSO) | `vault-secrets-operator` (Certified) | `stable` | `vault-secrets-operator.v1.0.1` | `oc get csv -n hashicorp-vault-secrets-operator --selector=operators.coreos.com/vault-secrets-operator.vault-secrets-operator` | https://developer.hashicorp.com/vault/docs/platform/k8s/vso |
| Vault Config Operator (VCO) | `vault-config-operator` (Community) | `alpha` | `vault-config-operator.v0.8.35` | `oc get csv -n vault-config-operator --selector=operators.coreos.com/vault-config-operator.vault-config-operator` | https://github.com/redhat-cop/vault-config-operator/tree/v0.8.35 |
| Couchbase Autonomous Operator (CAO) | Helm chart `couchbase/couchbase-operator` | Chart `2.81.1` (deploys CAO 2.8.1 build 164) | `helm list -n bitiq-local | grep cb-operator` | `helm status -n bitiq-local cb-operator` | https://docs.couchbase.com/operator/2.8/overview.html |
| OpenShift cert-manager Operator | `openshift-cert-manager-operator` (Red Hat) | `stable-v1` | `cert-manager-operator.v1.17.0` | `oc get csv -n openshift-operators --selector=operators.coreos.com/openshift-cert-manager-operator.openshift-operators` | https://docs.openshift.com/container-platform/4.19/security/cert_manager_operator/about-cert-manager-operator.html |

## Workload Components

| Component | Version | Verification | Documentation |
|-----------|---------|--------------|---------------|
| Couchbase Server (local) | `couchbase/server:7.6.6` | `oc -n bitiq-local get couchbasecluster couchbase-cluster -o jsonpath='{.spec.image}'` | https://docs.couchbase.com/server/7.6/introduction/intro.html |

> _Add additional services (Strfry, nostr workloads, etc.) to this matrix as they land in GitOps. Include the exact container tag or release and a stable documentation link for that version._

## Verification Reference

After bootstrap or an upgrade, run:

```bash
# CRC & cluster
crc version
oc version

# Operators
oc get csv -A | grep openshift-gitops-operator
oc get csv -A | grep openshift-pipelines-operator-rh
oc get csv -A | grep vault-secrets-operator
oc get csv -A | grep vault-config-operator
oc get csv -A | grep cert-manager-operator

# Couchbase (Helm release + payload)
helm list -n bitiq-local | grep cb-operator
oc -n bitiq-local get couchbasecluster couchbase-cluster -o jsonpath='{.spec.image}'
```

Record any deviations from the matrix in your PR description and update the table before merging.
