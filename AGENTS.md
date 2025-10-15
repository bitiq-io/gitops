# AGENTS.md — Bitiq GitOps Repository

Purpose: Guide AI/dev assistants and contributors working in this GitOps repo (Helm-first Argo CD + Tekton). Changes here impact cluster state via Argo CD.

## Golden Rules (GitOps‑first)

- Small, reviewable PRs; one purpose per PR.
- Never commit secrets, kubeconfigs, or tokens. Secrets are sourced exclusively via Vault operators — HashiCorp Vault Secrets Operator (VSO) for runtime delivery and Red Hat COP Vault Config Operator (VCO) for Vault control-plane configuration.
- Follow Conventional Commits. Common scopes: `charts`, `umbrella`, `pipelines`, `image-updater`, `operators`.
- Enforce the versioning and naming rules in `docs/CONVENTIONS.md` (image tags, composite appVersion, env overlays).
- Keep operator versions aligned with `docs/OPERATOR-VERSIONS.md` (channels, CSVs, and reference docs).
- Rollbacks happen in Git: use `docs/ROLLBACK.md`. Do not patch live resources to “fix” state — reconcile via Git.
- Do not change operator channels or critical defaults without explicit approval and notes in the PR body.
- Git is the source of truth. Do not create or mutate Kubernetes resources by hand. The only sanctioned cluster‑side scripts are:
  - `scripts/bootstrap.sh` — installs operators (OLM Subscriptions), sets up ApplicationSet + umbrella apps, and waits for CRDs/CSVs.
  - `scripts/dev-vault.sh` — local‑only helper to spin up dev Vault, seed `gitops/data/...` paths, apply VCO/VSO minimal CRs, and let VSO reconcile secrets. It also links `quay-auth` to Tekton `pipeline` SA and restarts Image Updater for token pickup.
- Validate templates locally before opening a PR (`make validate`).

### Secrets Policy (Mandatory Vault via VSO/VCO)

- All credentials and runtime secrets must flow from Vault: VCO manages Vault config (auth mounts/roles/policies) and VSO syncs to Kubernetes Secrets. Examples:
  - Argo CD Image Updater token → `gitops/data/argocd/image-updater` → `openshift-gitops/argocd-image-updater-secret` (VSO-managed).
  - Quay dockerconfig → `gitops/data/registry/quay` → `openshift-pipelines/quay-auth` (VSO-managed).
  - GitHub webhook → `gitops/data/github/webhook` → `openshift-pipelines/github-webhook-secret` (VSO-managed).
- Apps consume secrets through chart values (`backend.secret.*`, `frontend.secret.*`), not literal env defaults.
- Local development: run `make dev-vault` to seed demo values; rotate by writing to Vault and re‑running the helper. Do not use `oc create secret`.

### Anti‑patterns (disallowed)

- `oc create secret …` or manual mutation of cluster resources to “unblock” changes. Fix manifests in Git or seed Vault for VSO to reconcile.
- Editing Argo CD Applications in the UI. Change templates/values and let Argo reconcile.
- Ad‑hoc operator channel bumps. Propose in a PR with release notes and maintainers’ approval.

### Exceptions (time‑boxed, documented)

- Diagnosing production incidents may require one‑off `oc get`, logs, and read‑only inspection. If any write is unavoidable, document it in the incident and open a PR immediately to codify the change.
- Initial cluster bring‑up follows `scripts/bootstrap.sh`. For local CRC parity only, `make dev-vault` is permitted to demonstrate Vault flows — it does not replace Git as the source of truth; it seeds Vault so VSO can reconcile.

## Repo Map

- `charts/bootstrap-operators/` — OLM Subscriptions and optional Argo CD instance
- `charts/argocd-apps/` — ApplicationSet generating the umbrella Application per env
- `charts/bitiq-umbrella/` — Deploys sub-apps (image-updater, pipelines, sample app)
- `charts/ci-pipelines/` — Tekton pipelines and triggers
- `charts/image-updater/` — Argo CD Image Updater deployment
- `charts/eso-vault-examples/` — REMOVED in T17. ESO is deprecated; use VSO (runtime) + VCO (control plane). For historical context, see docs/ESO-TO-VSO-MIGRATION.md.
- `charts/toy-service/` — Backend sample service (Deployment + Service + Route)
- `charts/toy-web/` — Frontend sample web app (Deployment + Service + Route)
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
make verify-release  # check appVersion vs values-<env>.yaml image tags
make dev-setup  # install local commit-msg hook for commitlint
```

- GitHub Actions (`.github/workflows/validate.yaml`) runs these same targets on PR/push; keep them green locally before sending changes.

CI uses the same entrypoint: the GitHub workflow runs `make validate` to keep local and CI checks aligned.

For Single-Node OpenShift parity work, follow `docs/SNO-RUNBOOK.md` and run `./scripts/sno-preflight.sh` before invoking `scripts/bootstrap.sh`.
Note: SNO requires out‑of‑band ignition/discovery ISO and cannot be sanity‑checked locally like CRC. Prefer `ENV=local` for quick validation.

For production secrets management, follow `docs/PROD-SECRETS.md`. ESO content is transitional; the umbrella deploys VSO/VCO per env when `vault.runtime.enabled=true` and suppresses the ESO examples to avoid dual writers. Bootstrap installs the VSO/VCO operators and waits for CRDs.

If adding/altering Helm values:

```bash
export ENV=local  # or sno|prod
helm template charts/bitiq-umbrella -f charts/bitiq-umbrella/values-common.yaml \
  -f charts/toy-service/values-${ENV}.yaml \
  -f charts/toy-web/values-${ENV}.yaml >/dev/null
```

## Commit & PR Conventions

- Branch names: `docs/...`, `feat(charts): ...`, `fix(umbrella): ...`, `chore(pipelines): ...`
- Use Conventional Commits with scopes where useful.
- Include env impact in the PR description (e.g., affects local|sno|prod values).
- Creating PRs via GitHub CLI:
  - Prefer `gh pr create --fill` to use the PR template and commit body
  - If providing a custom body, use `--body-file <file>` to avoid literal `\n`
 - For multi-line commit messages, avoid literal `\n` in `git commit -m`.
   Use `git commit -F <file>` or a heredoc (e.g., `git commit -F- <<'EOF' ... EOF`) so newlines render correctly.

## Safety & Out of Scope

- Do not hardcode domains, tokens, or passwords in charts/values; use placeholders and document required env vars.
- Avoid changing multiple envs in one PR unless necessary; call it out explicitly.
- Coordinate operator channel changes with maintainers; include references (release notes/docs).
- When introducing additional secrets tooling, add usage docs and examples. Prefer VSO/VCO; ESO is deprecated and only retained as a legacy fallback.

Notes for agents (local e2e):
- Do not auto-create GitHub webhook secrets in charts without an explicit opt-in; use `triggers.createSecret=true` for that behavior.
- Prefer creating Argo CD API tokens for a dedicated local account (`argocd-image-updater`) over SSO users for use by automation.
- When configuring repo credentials, run `argocd login $(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}') --sso --grpc-web` first, then `argocd repo add https://github.com/bitiq-io/gitops.git --username <user> --password $GH_PAT --grpc-web`. Sanity-check the PAT with `curl` + `git ls-remote` so GitHub marks it “Last used”.

## References

- Ecosystem standards and templates: https://github.com/PaulCapestany/ecosystem
- Canonical repo conventions: docs/CONVENTIONS.md
- Rollback runbook: docs/ROLLBACK.md
- SNO runbook & preflight: docs/SNO-RUNBOOK.md, scripts/sno-preflight.sh
- Argo CD, Pipelines, Image Updater links are in this repo’s README.
