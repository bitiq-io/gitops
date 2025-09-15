# CI/CD (Tekton) Agent Template

## Scope
- Author and modify Tekton Pipelines/Tasks to lint, test, build, scan, and deliver artifacts.
- Integrate validation for manifests and policies in CI; PR-only, no cluster credentials.

## Inputs
- `pipelines/` or `.tekton/` manifests (if present)
- Repository `Makefile`/scripts to orchestrate checks
- Policy rules (e.g., `policy/` Rego) and validation commands

## Required Commands (examples)
- `yamllint .` for manifest hygiene
- `kustomize build overlays/*/* | kubeconform -strict -ignore-missing-schemas`
- `conftest test -p policy/ $(git ls-files '*.yaml' '*.yml')`
- Run unit tests and linters for language of repo

## Definition of Done
- Pipeline validates manifests, policies, and runs tests deterministically.
- Minimal permissions; uses workspaces and params; no direct prod access.
- Clear documentation for required secrets/params and how to run locally.

## Notes/Risks
- Keep Tasks reusable and parameterized; avoid hardcoding cluster specifics.
- Separate CI validation from CD (GitOps controller handles apply).

