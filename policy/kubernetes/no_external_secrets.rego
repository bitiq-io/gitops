package kubernetes.external_secrets

# Disallow committing ExternalSecret resources in Git-managed charts.
# VSO/VCO are the enforced path per T6/T17; ESO manifests should not be present.

deny contains msg if {
  input.apiVersion == "external-secrets.io/v1beta1"
  input.kind == "ExternalSecret"
  name := input.metadata.name
  ns := input.metadata.namespace
  msg := sprintf("Do not commit ExternalSecret manifests (%s/%s). Use VSO/VCO (VaultStaticSecret).", [ns, name])
}
