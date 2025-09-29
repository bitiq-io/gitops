# ENV=prod Parity Execution Plan (Agent‑Actionable)

Purpose: Achieve end‑to‑end parity for ENV=prod with ENV=local across Argo CD, Tekton, and sample application flows on OCP 4.19. Plan favors small, reviewable PRs and aligns with AGENTS.md Golden Rules.

## Current State (assessment)
- ApplicationSet defines `envs[]` for `prod` with `clusterServer=https://kubernetes.default.svc`, `appNamespace=bitiq-prod`, `baseDomain=apps.prod.example` (charts/argocd-apps/values.yaml).
- Umbrella chart generates nested Argo Applications whose destinations are hardcoded to in‑cluster (`https://kubernetes.default.svc`).
- Bootstrap script sets `envFilter` and `baseDomainOverride`, but does not override `clusterServer` (scripts/bootstrap.sh).
- Sample app has `values-prod.yaml` including baseDomain and deterministic image tags (charts/bitiq-sample-app/values-prod.yaml).
- CI templates/lint/validate include `prod` in loops (Makefile, .github/workflows/validate.yaml).

Conclusion: Plumbing exists to render a `bitiq-umbrella-prod` app, and the sample app has a prod overlay. Remaining production gaps include:
- Operator channels are set to `latest` (charts/bootstrap-operators/values.yaml); pin versions compatible with OCP 4.19.
- Secrets management (Image Updater token, webhook secret, registry creds) is manual; document SealedSecrets/ESO paths.
- Production hardening guidance (RBAC, Tekton quotas, observability) needs to be captured.

## Decision: Management Model for prod
- Default (recommended): In‑cluster Argo CD per prod cluster (matches local/SNO). This requires setting `prod.clusterServer=https://kubernetes.default.svc`.
- Optional (advanced): Central Argo managing prod remotely. This requires: registering prod cluster with Argo (`argocd cluster add`), parameterizing nested Application destinations to the remote cluster, and ensuring CRDs (Application) exist only in the control cluster.

We will implement the in‑cluster model by default and document the central model as an alternative with explicit steps.

## Branching & Validation
- Branch naming: `docs/prod-parity-plan`, then feature branches per task.
- Always run: `make lint`, `make hu`, `make template`, `make validate`, `make verify-release` before PR.
- Follow Conventional Commits; include env impact in PR descriptions.

## Work Plan (small, verifiable PRs)

1) Add PROD Runbook (docs)
- Change: Create `docs/PROD-RUNBOOK.md` with copy‑pastable steps to bootstrap ENV=prod on OCP 4.19.
- Must include: prerequisites (cluster‑admin, base domain, storage), pinning operator channels, oc login, bootstrap (ENV=prod BASE_DOMAIN=...), secrets (ArgoCD repo creds, Image Updater token, Quay creds, webhook secret), smoke tests, and rollback.
- Include both models: default in‑cluster; optional central Argo section with `argocd cluster add` and ApplicationSet value adjustments.
 - Commit: `docs(prod): add OCP 4.19 prod runbook`
 - Acceptance: Steps reproduce a healthy `bitiq-umbrella-prod`; routes reachable; pipelines and image updater functioning.
  - Status: ✅ Completed in branch `feat/prod-parity` (docs/PROD-RUNBOOK.md).

2) Add PROD preflight script
- Change: Add `scripts/prod-preflight.sh` mirroring SNO preflight, tailored for multi‑node prod.
- Checks: oc login; >=3 Ready worker nodes; default StorageClass; BASE_DOMAIN set; wildcard DNS resolves for `*.${BASE_DOMAIN}` or document TLS/ingress expectations; Operators (GitOps, Pipelines) subscription status (or not installed yet); cluster version >=4.19; required namespaces exist or will be created; warn if operator channels not pinned.
- Exit non‑zero on blockers; print remediation tips.
  - Commit: `feat(scripts): add prod preflight checks (login/nodes/storage/DNS/operators)`
  - Acceptance: Running script yields PASS/FAIL per check with clear guidance.
  - Status: ✅ Completed in branch `feat/prod-parity` (scripts/prod-preflight.sh).

3) Align ApplicationSet for in‑cluster prod (default)
- Change: Update `charts/argocd-apps/values.yaml` to set `prod.clusterServer=https://kubernetes.default.svc`.
- Rationale: Nested Applications deploy with `destination.server: https://kubernetes.default.svc`, so the umbrella Application must also render in the Argo control cluster when using in‑cluster model.
  - Commit: `fix(argocd-apps): set prod clusterServer to in‑cluster by default`
  - Acceptance: `helm template` for `ENV=prod` produces a consistent app‑of‑apps that syncs without CRD conflicts.
  - Note: If central model is desired, we will not change this default; instead, add templating to drive nested destinations via ApplicationSet vars (see task 8). This change is gated on your approval due to its environment impact.
  - Status: ✅ Completed in branch `feat/prod-parity` (charts/argocd-apps/values.yaml).

4) Pin operator channels for OCP 4.19
- Change: Update `charts/bootstrap-operators/values.yaml` to pin `operators.gitops.channel` and `operators.pipelines.channel` to versions compatible with OCP 4.19 (see References). Add release note links in a doc comment.
- Commit: `chore(operators): pin GitOps & Pipelines channels for OCP 4.19`
- Acceptance: Subscriptions install specific channels; preflight confirms.
- Gate: Per AGENTS.md, do not change operator channels without explicit approval. Will include rationale + references in PR body.

5) Secrets management for prod (doc + optional charts)
- Change: Document recommended approaches: External Secrets Operator (ESO) or SealedSecrets. Provide minimal examples for:
  - Argo CD Image Updater token (`openshift-gitops/argocd-image-updater-secret`).
  - Quay registry creds for the `pipeline` SA in `openshift-pipelines`.
  - GitHub webhook secret (`openshift-pipelines/github-webhook-secret`).
- Optional: Add a new chart `charts/secrets-examples/` with disabled‑by‑default examples using ESO or SealedSecrets (no real data, placeholders only).
- Commit: `docs(secrets): add prod secrets guidance (+ optional examples chart)`
- Acceptance: Clear, safe paths to manage secrets without committing sensitive data.

6) Argo CD hardening (prod)
- Change (docs + values guidance):
  - Optionally set `disableDefaultInstance: true` and create a managed `ArgoCD` CR with RBAC and SSO guidance.
  - Recommend dedicated Argo CD account for Image Updater with minimal permissions; include CLI steps to generate token and store it via the chosen secrets approach.
- Commit: `docs(gitops): add prod RBAC/SSO guidance and image-updater account`
- Acceptance: Runbook contains concrete commands; no defaults changed without approval.

7) Tekton hardening (prod)
- Change (docs): quotas and security context guidance for `openshift-pipelines`; linking secrets; optional PVC template sizing; TLS verify set appropriately; use of internal registry if desired.
- Optional: Add `ciPipelines.fsGroup` and per‑pipeline overrides already exist; document prod‑safe values.
- Commit: `docs(pipelines): add prod guidance for SA, creds, and quotas`
- Acceptance: Pipelines run in prod with proper permissions and registry access.

8) Central Argo (documentation only, no code now)
- Change: Document an advanced “central Argo” model in the PROD runbook: registering clusters with `argocd cluster add`, credential scope/rotation, network requirements, and capacity considerations.
- No chart changes or feature flags now. Revisit only if we explicitly decide to adopt central control.

9) Smoke & validation for prod
- Change: Add `make smoke ENV=prod BASE_DOMAIN=...` docs; optionally add `scripts/prod-smoke.sh` wrapper that calls preflight, then tails app health and image‑updater logs.
- Commit: `chore(scripts): add prod smoke wrapper` (optional)
- Acceptance: One‑liner smoke works post‑bootstrap.

10) README updates
- Change: Add a concise prod section pointing to the runbook, with quick‑start and secrets notes.
- Commit: `docs(readme): add prod quick path and link runbook`
- Acceptance: Clear path from README to full prod docs.

## Execution Checklist (per task)
- Create a focused branch per task; keep PRs small.
- Obey AGENTS.md conventions; call out env impact and any channel changes in PR bodies.
- Run `make lint`, `make hu`, `make template`, `make validate`, and, when applicable, the new preflight.
- Avoid committing secrets; prefer ESO/SealedSecrets with placeholders.

## Acceptance Criteria (parity)
- Bootstrap on OCP 4.19 with `ENV=prod` yields:
  - Argo Application `bitiq-umbrella-prod` Healthy/Synced in `openshift-gitops`.
  - Namespace `bitiq-prod` exists; toy backend/frontend Routes resolve on `${BASE_DOMAIN}` and serve 200s.
  - Tekton PipelineRuns build and push images to the configured registry using the `pipeline` SA.
  - Argo CD Image Updater detects new tags and writes back to `charts/bitiq-sample-app/values-prod.yaml` on the tracked branch.
- Operator channels pinned and documented; preflight passes on a fresh 4.19 cluster.
- Alternative central‑Argo path documented (and optionally implemented behind a flag).

## References (OCP 4.19 / current)
- OCP 4.19 product docs: https://docs.redhat.com/en/documentation/openshift_container_platform/4.19
- OpenShift GitOps docs: https://docs.openshift.com/gitops/latest/ (redirects to the latest GitOps guide)
- OpenShift Pipelines docs: https://docs.openshift.com/pipelines/latest/ (redirects to the latest Pipelines guide)
- Argo CD Image Updater: https://argocd-image-updater.readthedocs.io/en/stable/
- Compatibility (pin channels): consult the OpenShift GitOps and Pipelines release notes for versions compatible with OCP 4.19 before pinning.
