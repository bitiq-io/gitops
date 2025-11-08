package gitops.applicationset_guardrails

# Ensure the ApplicationSet wires required Helm parameters to the umbrella chart.
# This prevents accidental omissions in env parameterization that can lead to
# incorrect or incomplete child Applications.

is_appset if {
  input.apiVersion == "argoproj.io/v1alpha1"
  input.kind == "ApplicationSet"
}

# Set of parameter names in the ApplicationSet's Helm source
param_names contains s if {
  is_appset
  p := input.spec.template.source.helm.parameters[_]
  s := p.name
}

required := [
  "env",
  "baseDomain",
  "appNamespace",
  "repoUrl",
  "targetRevision",
  "imageUpdater.platforms",
  "ciPipelines.fsGroup",
  "vault.runtime.enabled",
  "vault.config.enabled",
]

missing contains r if {
  is_appset
  r := required[_]
  not param_names[r]
}

deny contains msg if {
  is_appset
  r := missing[_]
  msg := sprintf("ApplicationSet missing required helm parameter: %s", [r])
}
