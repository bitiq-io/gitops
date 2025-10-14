package kubernetes.secrets

# Disallow committing Kubernetes Secret manifests in Git-managed charts.
# All secrets must be sourced via Vault operators (VSO for runtime, VCO for Vault config).

deny contains msg if {
  input.kind == "Secret"
  name := input.metadata.name
  ns := input.metadata.namespace
  msg := sprintf("Do not create Secrets in Git-managed charts (%s/%s). Use Vault via VSO/VCO.", [ns, name])
}
