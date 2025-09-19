# AGENTS.md — Bitiq GitOps Repository

Purpose: Guide AI/dev assistants and contributors working in this GitOps repo (Helm-first Argo CD + Tekton). Changes here impact cluster state via Argo CD.

## Golden Rules

- Prefer small, reviewable PRs; one purpose per PR.
- Never commit secrets, kubeconfigs, or tokens. Use SealedSecrets/External Secrets when introduced.
- Follow Conventional Commits. Common scopes: `charts`, `umbrella`, `pipelines`, `image-updater`, `operators`.
- Enforce the versioning and naming rules in `docs/CONVENTIONS.md` (image tags, composite appVersion, env overlays).
- Rollbacks happen in Git: use `docs/ROLLBACK.md` and avoid cluster-side edits.
- Do not change operator channels or critical defaults without explicit approval and notes in the PR body.
- Avoid cluster-side manual changes; Git is the source of truth. Use `scripts/bootstrap.sh` only for initial operator installs.
- Validate templates locally before opening a PR.

## Repo Map

- `charts/bootstrap-operators/` — OLM Subscriptions and optional Argo CD instance
- `charts/argocd-apps/` — ApplicationSet generating the umbrella Application per env
- `charts/bitiq-umbrella/` — Deploys sub-apps (image-updater, pipelines, sample app)
- `charts/ci-pipelines/` — Tekton pipelines and triggers
- `charts/image-updater/` — Argo CD Image Updater deployment
- `charts/bitiq-sample-app/` — Example app used for end-to-end flow
- `scripts/bootstrap.sh` — One-time/occasional bootstrapping for operators + initial apps
- `scripts/validate.sh` — Local validation (render + schema + policy)
- `Makefile` — Lint, template sanity, and full validate

## Golden Paths (Local Validation)

Run basic checks before committing:

```bash
make lint       # helm lint all charts
make hu         # helm-unittest suites (helm plugin required)
make template   # helm template sanity (uses env values)
make validate   # render charts, kubeconform, conftest, yamllint
make dev-setup  # install local commit-msg hook for commitlint
```

CI uses the same entrypoint: the GitHub workflow runs `make validate` to keep local and CI checks aligned.

If adding/altering Helm values:

```bash
export ENV=local  # or sno|prod
helm template charts/bitiq-umbrella -f charts/bitiq-umbrella/values-common.yaml \
  -f charts/bitiq-sample-app/values-${ENV}.yaml >/dev/null
```

## Commit & PR Conventions

- Branch names: `docs/...`, `feat(charts): ...`, `fix(umbrella): ...`, `chore(pipelines): ...`
- Use Conventional Commits with scopes where useful.
- Include env impact in the PR description (e.g., affects local|sno|prod values).
- Creating PRs via GitHub CLI:
  - Prefer `gh pr create --fill` to use the PR template and commit body
  - If providing a custom body, use `--body-file <file>` to avoid literal `\n`

## Safety & Out of Scope

- Do not hardcode domains, tokens, or passwords in charts/values; use placeholders and document required env vars.
- Avoid changing multiple envs in one PR unless necessary; call it out explicitly.
- Coordinate operator channel changes with maintainers; include references (release notes/docs).
- When introducing secrets management (SealedSecrets/ESO), add usage docs and examples.

Notes for agents (local e2e):
- Do not auto-create GitHub webhook secrets in charts without an explicit opt-in; use `triggers.createSecret=true` for that behavior.
- Prefer creating Argo CD API tokens for a dedicated local account (`argocd-image-updater`) over SSO users for use by automation.
- When configuring repo credentials, run `argocd login $(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}') --sso --grpc-web` first, then `argocd repo add https://github.com/bitiq-io/gitops.git --username <user> --password $GH_PAT --grpc-web`. Sanity-check the PAT with `curl` + `git ls-remote` so GitHub marks it “Last used”.

## References

- Ecosystem standards and templates: https://github.com/PaulCapestany/ecosystem
- Canonical repo conventions: docs/CONVENTIONS.md
- Rollback runbook: docs/ROLLBACK.md
- Argo CD, Pipelines, Image Updater links are in this repo’s README.
