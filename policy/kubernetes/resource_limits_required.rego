package kubernetes.resources

deny contains msg if {
  input.kind == "Deployment"
  some i
  c := input.spec.template.spec.containers[i]
  not c.resources
  msg := sprintf("container %q missing resources", [c.name])
}

deny contains msg if {
  input.kind == "Deployment"
  some i
  c := input.spec.template.spec.containers[i]
  not c.resources.limits
  msg := sprintf("container %q missing resource limits", [c.name])
}

deny contains msg if {
  input.kind == "Deployment"
  some i
  c := input.spec.template.spec.containers[i]
  not c.resources.requests
  msg := sprintf("container %q missing resource requests", [c.name])
}
