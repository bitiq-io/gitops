# AGENTS.md — GitOps Repository

Purpose: Guide AI/dev assistants working in the GitOps repo. Focus on validation, policy, and safe changes via PRs.

## Golden Rules
- PR-only; no direct cluster access. No secrets in repo (use SOPS if needed).
- Keep structure stable (`apps/<app>/{base,overlays}`); propose ADRs for structural changes.
- Validate everything: yamllint, kustomize+kubeconform, conftest.
- Use Conventional Commits; small, reviewable PRs.

## Commands
- Lint: `yamllint -c .yamllint.yaml .` (fallback to default)
- Validate overlays: `for k in $(git ls-files | grep 'overlays/.*/.*/kustomization.yaml'); do kustomize build $(dirname "$k") | kubeconform -strict -ignore-missing-schemas; done`
- Policy: `conftest test -p policy $(git ls-files '*.yaml' '*.yml')`

## Definition of Done
- All above commands pass locally and in CI.
- ADR added/updated for structural or policy-impacting changes.
- No plaintext secrets; image digests preferred; securityContext adheres to policies.

## Roles (agents/)
- `infra-argocd.md` — Argo CD layout and Applications/ApplicationSets
- `infra-tekton.md` — CI validation pipeline tasks
- `planner.md` — Break down work with acceptance criteria
- `architect.md` — Propose structure; draw boundaries
- `tester.md` — Validation plans and test harnesses
- `security.md` — Policy rules and remediations
