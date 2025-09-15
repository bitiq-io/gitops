package kubernetes.security

deny[msg] {
  input.kind == "Deployment"
  sc := input.spec.template.spec.securityContext
  not sc.runAsNonRoot
  msg := "pod securityContext.runAsNonRoot must be true"
}

deny[msg] {
  input.kind == "Deployment"
  some i
  c := input.spec.template.spec.containers[i]
  sc := c.securityContext
  not sc.runAsNonRoot
  msg := sprintf("container %q securityContext.runAsNonRoot must be true", [c.name])
}
