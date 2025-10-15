package gitops.dual_secret_operators

# Deny if umbrella renders both ESO and VSO apps in the same env.
# This policy is intended to run against the rendered umbrella chart output
# (a multi-doc YAML). It detects Argo CD Application resources named with the
# expected prefixes and blocks the case where both are present.

deny contains msg if {
  some i
  input[i].apiVersion == "argoproj.io/v1alpha1"
  input[i].kind == "Application"
  startswith(input[i].metadata.name, "eso-vault-examples-")

  some j
  input[j].apiVersion == "argoproj.io/v1alpha1"
  input[j].kind == "Application"
  startswith(input[j].metadata.name, "vault-runtime-")

  env := split(input[i].metadata.name, "-")[count(split(input[i].metadata.name, "-")) - 1]
  env == split(input[j].metadata.name, "-")[count(split(input[j].metadata.name, "-")) - 1]

  msg := sprintf("Do not enable ESO and VSO together for env '%s'. Gate via umbrella values.", [env])
}
