package kubernetes.image

deny[msg] {
  input.kind == "Deployment"
  some i
  container := input.spec.template.spec.containers[i]
  endswith(container.image, ":latest")
  msg := sprintf("container %q uses :latest tag", [container.name])
}
