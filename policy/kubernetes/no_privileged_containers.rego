package kubernetes.security

deny contains msg if {
  input.kind == "Deployment"
  some i
  c := input.spec.template.spec.containers[i]
  sc := c.securityContext
  sc.privileged
  msg := sprintf("container %q must not run privileged", [c.name])
}
