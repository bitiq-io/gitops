# ADR-0002: Helm-first GitOps Structure

## Status
Accepted

## Context
This repository manages cluster state for Bitiq environments via Argo CD. The current implementation, charts, and Makefile are Helm-first. Earlier proposals suggested adopting a Kustomize overlays layout. We need a clear decision to guide CI validation, documentation, and future contributions.

## Decision
- Keep the repository Helm-first.
- Use Helm charts for all deployable components (operators bootstrap, Argo CD apps, umbrella, image-updater, pipelines, sample app).
- Generate environment-specific Argo CD Applications via an ApplicationSet (the `argocd-apps` chart) using a simple `envFilter` parameter.
- Validate rendered manifests from Helm charts in CI and locally:
  - Schema validation with `kubeconform` (ignore missing schemas for CRDs)
  - Policy checks with `conftest` against Rego rules under `policy/`
  - YAML linting only for non-template YAML (exclude `charts/**/templates/**`).

## Consequences
- Contributors focus on Helm values and charts; no parallel Kustomize overlays are required.
- CI and local validation render Helm templates before running linters/policy, avoiding false positives from Go templates.
- Custom resources from Argo CD, Tekton, and OLM are tolerated during validation (schema ignored) while native Kubernetes objects are strictly validated and policy-checked.

## Alternatives Considered
- Kustomize bases/overlays for apps and environments: flexible, but diverges from current Helm-first design and would duplicate effort.

## References
- Makefile targets: `lint`, `template`, `validate`
- Policy rules: `policy/kubernetes/*.rego`
- CI workflow: `.github/workflows/gitops-validate.yml`
