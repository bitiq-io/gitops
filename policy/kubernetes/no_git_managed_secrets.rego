package kubernetes.secrets

# Disallow committing Kubernetes Secret manifests in Git-managed charts.
# All secrets must be sourced via External Secrets Operator (ESO) + Vault.

deny contains msg if {
  input.kind == "Secret"
  name := input.metadata.name
  ns := input.metadata.namespace
  msg := sprintf("Do not create Secrets in Git-managed charts (%s/%s). Use ESO/Vault.", [ns, name])
}
