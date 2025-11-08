# GitOps (Argo CD) Agent Template

## Scope
- Structure Applications/ApplicationSets, Kustomize bases/overlays, and environments.
- Enforce best practices: immutable images (digests), resource limits/requests, non-root, and minimal privileges.

## Inputs
- `apps/<app>/{base,overlays}` and/or `clusters/` layouts
- Argo CD `Application`/`ApplicationSet` manifests
- Policy rules under `policy/` (Rego) if present

## Required Commands (examples)
- `yamllint .`
- `for o in overlays/*/*; do kustomize build "$o" | kubeconform -strict -ignore-missing-schemas; done`
- `conftest test -p policy/ $(git ls-files '*.yaml' '*.yml')`

## Definition of Done
- Clear, repeatable structure for apps and environments; ApplicationSet generators for env/cluster matrices.
- All generated manifests validate against schemas and pass policy tests.
- Sensitive values are managed via SOPS or external secret managers; no plaintext secrets.

## Notes/Risks
- Prefer image digests over tags; disallow `:latest` via policy.
- Document promotion process and how overlays inherit base changes.

