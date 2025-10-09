# ENV=sno Parity Execution Plan (Agent‑Actionable)

Purpose: Achieve end‑to‑end parity for ENV=sno with ENV=local across Argo CD, Tekton, and sample application flows. Plan is structured for Codex agents to implement, validate, and commit in small PRs.

## Current State (verified in repo)
- SNO destination server set to in‑cluster: charts/argocd-apps/values.yaml (sno.clusterServer=https://kubernetes.default.svc)
- BASE_DOMAIN plumbed through bootstrap → ApplicationSet via `baseDomainOverride`: scripts/bootstrap.sh, charts/argocd-apps/templates/applicationset-umbrella.yaml
- Tekton fsGroup already optional: charts/ci-pipelines/values.yaml (fsGroup:""), templates guard in triggers.yaml
- Image namespace creation gated: charts/ci-pipelines/values.yaml (createImageNamespaces:false)
- README contains SNO notes, but there is no full SNO runbook covering cluster provisioning and preflight checks.

Conclusion: Most chart plumbing for ENV=sno is done. Remaining gap is a reproducible SNO setup/runbook and a lightweight preflight to catch common issues before bootstrap.

## Branching & Commit
- Branch: docs/sno-parity-plan
- Style: Conventional Commits, one purpose per PR
- Validation before PR: `make lint`, `make hu`, `make template`, `make validate`

## Work Plan (small, verifiable PRs)

1) Add SNO Runbook (docs)
- Change: Create docs/SNO-RUNBOOK.md with copy‑pastable steps to provision SNO and bootstrap this repo.
- Must include: prerequisites, Assisted/Agent install links, DNS and BASE_DOMAIN guidance, storage default, oc login, bootstrap, secrets (webhook, Image Updater, Quay), smoke tests, central ArgoCD variant, disconnected notes, troubleshooting.
- Files: docs/SNO-RUNBOOK.md
- Commit: docs(sno): add SNO runbook for ENV=sno
- Acceptance: Document renders locally; commands are self‑contained; links point to OCP 4.18/GitOps/Pipelines 1.16 and Image Updater docs.

2) Update README to point to Runbook
- Change: Replace the current SNO notes block with a concise summary and a prominent link to docs/SNO-RUNBOOK.md. Keep quick‑start commands (ENV, BASE_DOMAIN, bootstrap, make smoke) in README.
- Files: README.md
- Commit: docs(readme): link SNO runbook and streamline SNO notes
- Acceptance: README quick‑start remains accurate; `make smoke ENV=sno` guidance visible.

3) Add preflight script for SNO
- Change: Add scripts/sno-preflight.sh to verify cluster readiness before bootstrap.
- Checks: oc login; exactly 1 Ready node; default StorageClass present; Operators (GitOps + Pipelines) CSVs Succeeded; BASE_DOMAIN provided; wildcard DNS (or named Routes) for BASE_DOMAIN resolves; show ArgoCD route if present.
- Exit: non‑zero on blockers, zero if all good; print remediation hints.
- Files: scripts/sno-preflight.sh (executable)
- Commit: feat(scripts): add SNO preflight checks (login/node/storage/DNS/operators)
- Acceptance: Running script on a SNO cluster reports PASS/FAIL for each check and returns appropriate code.

4) Optional: Add SNO smoke wrapper (non‑disruptive)
- Change: Create scripts/sno-smoke.sh that enforces ENV=sno, validates BASE_DOMAIN, runs preflight, then delegates to scripts/smoke.sh.
- Files: scripts/sno-smoke.sh (executable)
- Commit: chore(scripts): add sno-smoke wrapper around smoke.sh
- Acceptance: Wrapper prints route URL and Application health; exits non‑zero on missing BASE_DOMAIN or failed preflight.

5) Enrich AGENTS guidance
- Change: Add a Golden Path note pointing to SNO runbook and preflight in AGENTS.md.
- Files: AGENTS.md
- Commit: docs(agents): add SNO runbook and preflight to Golden Paths
- Acceptance: Clear instructions for contributors/agents to validate SNO locally before PRs.

6) Final validation and docs pass
- Commands: `make template`, `make validate`, open docs in IDE preview, run preflight and smoke on a SNO cluster.
- Commit (if any small fixes): chore(docs): polish SNO runbook examples
- Acceptance: All validations green; runbook steps executed successfully on an actual SNO cluster.

## Execution Checklist (per task)
- Create a feature branch per task.
- Make minimal, scoped changes to the files listed.
- Run local validation: `make lint`, `make hu`, `make template`, `make validate`.
- If scripts added: shellcheck locally (if available) and run on a target cluster when possible.
- Open PR with scope and ENV impact noted; link to SNO runbook if applicable.

## Acceptance Criteria (parity)
- A new user can provision SNO using linked docs, run preflight, bootstrap with ENV=sno and BASE_DOMAIN, and complete CI→CD flow:
  - ArgoCD Application bitiq-umbrella-sno is Healthy/Synced.
  - Sample app Routes resolve on BASE_DOMAIN and serve traffic.
  - Tekton PipelineRun builds/pushes images successfully.
  - Argo CD Image Updater detects new tags and writes back to charts/toy-service/values-sno.yaml and charts/toy-web/values-sno.yaml.
- No unintended Namespaces created by ci-pipelines chart; templates render cleanly for sno.

## Non‑Goals / Out of Scope
- Automating SNO provisioning itself (use Assisted/Agent installer docs).
- Managing credentials/secrets in Git; use manual creation or opt‑in flags.
- Changing operator channels or cluster‑level policies without explicit approval.

## References (OCP 4.18 / current)
- Installing on a Single Node (SNO): https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/installing_on_a_single_node
- OpenShift GitOps (Argo CD): https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/gitops
- OpenShift Pipelines 1.16: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.16
- Argo CD Image Updater: https://argocd-image-updater.readthedocs.io/en/stable/
