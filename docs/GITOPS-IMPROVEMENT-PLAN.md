1. id: T0
   name: Preflight & Version Pinning
   description: Add a preflight script to assert OCP compatibility, operator presence, default StorageClass, and node capacity; pin operator channels to GitOps 1.18 and Pipelines 1.20 in values and docs.
   why: Prevents drift from supported versions and avoids bootstrap failures; aligns with OpenShift GitOps 1.18 and Pipelines 1.20 install/config guidance.
   dependencies: []
   status: complete (merged via PR #35)
   acceptance_criteria:
     - charts/bootstrap-operators values specify channels: gitops-1.18 and pipelines-1.20.
     - scripts/preflight.sh returns 0 only if: OCP version in supported range for GitOps 1.18; GitOps & Pipelines Subscriptions InstallSucceeded; default StorageClass present.
     - README lists GitOps 1.18 and Pipelines 1.20 as prerequisites with links to official docs.
   notes: GitOps 1.18 install/config: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18; Pipelines 1.20 install/config: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20

2. id: T1
   name: Rollback — Single-Service (Git-first)
   description: Harden docs/ROLLBACK.md with a deterministic, copy/pasteable, Git-first rollback flow for a single microservice plus verification and failure fallbacks.
   why: Reduces operator error under pressure while keeping Git as source of truth; aligns with GitOps model.
   dependencies: [T0]
   status: complete (docs updated)
   acceptance_criteria:
     - ROLLBACK.md includes: git revert example, recompute umbrella/appVersion, argocd app sync/wait commands, and expected outputs.
     - Explicitly advises against cluster-side edits; documents CLI fallback only as emergency.
     - Smoke checks show restored tag and Healthy/Synced state.
   notes: GitOps 1.18 configuring: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/configuring_red_hat_openshift_gitops/

3. id: T2
   name: Rollback — Multi-Service + Updater Freeze
   description: Extend ROLLBACK.md with multi-service rollback steps and an updater freeze/unfreeze procedure to avoid immediate re-bumps during rollback windows.
   why: Multi-service changes are common; freezing avoids races; ensures composite versions reflect the intended state.
   dependencies: [T1]
   status: complete (docs updated)
   acceptance_criteria:
     - Docs include rolling back backend + frontend together with one commit and verifying composite appVersion.
     - Defines a reversible freeze (dry-run true or omit image-list) and re-enable steps with commands.
     - Verification shows both images at target tags and Argo reports Healthy/Synced.
   notes: Prefer Git changes for freeze where feasible; otherwise annotate temporarily and reconcile back to Git immediately after.

4. id: T3
   name: Image Updater Pause Toggles (per-image, per-env)
   description: Add values (imageUpdater.pause.backend/frontend) to conditionally render updater annotations per Application/environment, enabling safe freeze/unfreeze without ad-hoc edits.
   why: Improves operability for rollbacks/hotfixes; safer than manual annotation edits and preserves Git intent.
   dependencies: [T0, T2]
   status: complete (pause flags implemented; docs updated)
   acceptance_criteria:
     - Umbrella Application templates conditionally render image-list, update-strategy, platforms, and write-back annotations based on pause flags.
     - Defaults false; toggling true prevents write-back changes (verified via Argo UI and Git history).
     - README/ROLLBACK updated to reference pause flags.
   notes: Argo CD Image Updater annotations remain constrained to deterministic tag regex.

5. id: T4
   name: Sample App Split (per-service charts + Applications)
   description: Split current combined sample chart into `charts/toy-service` and `charts/toy-web`, with independent Argo Applications and write-back targets.
   why: Mirrors real microservice topology for scaling, health, and rollbacks; simplifies troubleshooting and aligns with best practices.
   dependencies: [T0, T3]
   status: complete (implemented in PR #39)
   acceptance_criteria:
     - New charts for each service with values-common and env overlays (local/sno/prod) exist; umbrella renders `toy-service-<env>` and `toy-web-<env>` Applications.
     - Image Updater annotations use distinct aliases and helmvalues write-back to each chart’s env values file.
     - `make template` and `argocd app diff` succeed; deployments become Ready on a test cluster.
   notes: Ensure compute-appversion/verify-release scripts are updated to handle two charts or move to per-app `appVersion`.

6. id: T5
   name: Sample App Placement Verification
   description: Confirm that sample deployment config is only in this repo; add cross-links in microservice READMEs and this repo’s README.
   why: Keeps repositories focused (app code vs. deployment); reduces duplication and drift.
   dependencies: [T4]
   status: complete (docs updated; READMEs linked)
   acceptance_criteria:
     - toy-service and toy-web repos contain no k8s manifests; issues/PRs add “Deployment via GitOps” links pointing here.
     - This repo’s README clearly states where runtime manifests live and how CI/Image Updater connects to microservice repos.
   notes: No relocation is needed given current repos; just document and link.

7. id: T6
   name: Secrets — Enforce ESO/Vault (Platform)
   description: Make ESO/Vault mandatory for all secrets (platform and app). Bootstrap installs ESO via OperatorHub; Git manages ClusterSecretStore and ExternalSecrets. No ad-hoc `oc create secret` flows remain.
   why: Enforces GitOps for credentials, eliminates manual CLI drift, and centralizes audit (Vault) and reconciliation (ESO).
   dependencies: [T0]
   status: planned (policy change + automation required)
   acceptance_criteria:
     - scripts/bootstrap.sh installs ESO Subscription (stable channel) automatically and waits for CRDs.
     - charts/eso-vault-examples renders by default with `enabled=true` for all envs; ClusterSecretStore configured via values.
     - All platform creds (argocd-image-updater token, quay dockerconfig, github webhook) are sourced exclusively via ExternalSecrets.
     - No Make targets or docs recommend creating Opaque secrets directly; CLI examples are removed or explicitly forbidden.
     - kubeconform validation of ESO resources is part of `make validate` (CRDs ignored as needed) for all envs.
   notes: Pipelines 1.20 configuring: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20/html/configuring_openshift_pipelines/

8. id: T7
   name: Secrets — toy-service via ExternalSecret
   description: Secret-backed env injection for toy-service (`backend.secret.*`, `backend.env`) with a required ExternalSecret (`toy-service-config`) across all envs.
   why: Demonstrates and enforces end-to-end secrets propagation for backend runtime.
   dependencies: [T6]
   status: complete (toy-service secrets wired; ESO enforced by policy)
   acceptance_criteria:
     - Deployment consumes env exclusively from ExternalSecret-backed Secret; no plain env defaults for sensitive data.
     - ExternalSecret renders by default and reconciles `toy-service-config` with required keys.
     - Local/CI template shows env wiring; `make validate` passes without opt-in flags.
   notes: Document Vault KV path and keys; require Vault seeding via automated script for local.

9. id: T8
   name: Secrets — toy-web via ExternalSecret
   description: Mirror T7 for frontend (`frontend.secret.*`, `frontend.env`) with a required ExternalSecret (`toy-web-config`) for sensitive runtime config.
   why: Completes secrets story for frontend runtime configuration with enforced ESO usage.
   dependencies: [T7]
   acceptance_criteria:
     - Deployment consumes sensitive env solely via ExternalSecret-backed Secret; non-sensitive values may use ConfigMap.
     - ExternalSecret renders by default and validates in `make validate` for all envs.
   notes: Keep non-sensitive params in ConfigMap where appropriate; no direct env literals for secrets.

10. id: T9
    name: Local Vault Automation (ENV=local)
    description: Replace Opaque secret fallback with automated local Vault + ESO flow. Provide a `make dev-vault` (or similar) target that deploys a dev Vault, seeds required KV paths, ensures ESO is installed, and reconciles ExternalSecrets for local.
    why: Preserves GitOps discipline locally; removes manual CLI secret creation and keeps parity with sno/prod.
    dependencies: [T6, T7, T8]
    acceptance_criteria:
      - `make dev-vault` deploys a dev Vault (ephemeral) or connects to a configured Vault, writes sample values to `gitops/data/...` paths.
      - scripts/bootstrap.sh detects/installs ESO in local and ensures ClusterSecretStore references the correct SA/role.
      - Pods in `bitiq-local` show env vars present via /internal/config; no Opaque secret creation path remains in docs.
    notes: Dev Vault must be clearly marked non-production; provide cleanup command.

11. id: T10
    name: Triggers & Registry Auth Hardening (ESO-only)
    description: EventListener and Tekton SA must consume secrets only via ESO-managed Secrets; replace `make quay-secret` with Vault seeding + ESO reconciliation. Document resolver versions.
    why: Eliminates manual secret management in CI; aligns with enforced ESO policy.
    dependencies: [T6]
    acceptance_criteria:
      - EventListener references ESO-managed GitHub secret; pipeline SA mounts ESO-managed Quay dockerconfig.
      - Provide `make dev-vault` seeding for required CI creds; remove direct `oc create secret` helper.
      - Docs updated with Pipelines 1.20 links and verification steps.
    notes: `triggers.createSecret` default remains false; all secrets sourced via Vault.

12. id: T11
    name: ApplicationSet Guardrails & Lint
    description: Tighten ApplicationSet generator scoping to intended envs/clusters; ensure `ignoreMissingValueFiles: true` and env parameterization are consistent; add lint/static checks.
    why: Prevents unintended app generation and keeps env overlays predictable.
    dependencies: [T0]
    acceptance_criteria:
      - ApplicationSet values include explicit env filters and correct param wiring for baseDomain/appNamespace/platforms/fsGroup.
      - `make validate` renders each env without missing values; conftest/policy checks (if present) pass.
    notes: Aligns with GitOps 1.18 usage patterns for ApplicationSets.

13. id: T12
    name: Operator Channels & Upgrade Guardrails
    description: Re-affirm pinned operator channels and require PR notes + maintainer approval before changing; add release notes links.
    why: Avoids accidental upgrades diverging from tested docs and runbooks.
    dependencies: [T0]
    acceptance_criteria:
      - bootstrap-operators values document channels with links to GitOps 1.18 and Pipelines 1.20 release notes.
      - AGENTS.md/README state the approval requirement; CI remains green after edits.
    notes: GitOps 1.18 release notes: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/release_notes/; Pipelines 1.20 release notes: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20/html/release_notes/

14. id: T13
    name: Validation Pipeline — ESO & AppSet Coverage
    description: Expand `make validate` to always render/validate ESO resources (no flag) and sanity-check ApplicationSet per env.
    why: Enforced ESO means validation must cover it by default.
    dependencies: [T6]
    acceptance_criteria:
      - `make validate` renders ESO with repo values and passes kubeconform (ignoring CRDs as needed).
      - Validation outputs show pass/fail clearly for each chart and env.
    notes: Keep runtime short; parallelize if needed.

15. id: T14
    name: Documentation Cross-links & Examples
    description: Update README and runbooks with explicit links to GitOps 1.18 and Pipelines 1.20 install/config, include enforced ESO/Vault usage, and local Vault automation.
    why: Keeps docs version-correct and reduces onboarding friction under the new policy.
    dependencies: [T1, T2, T3, T10]
    acceptance_criteria:
      - README/runbooks reference correct doc versions; ROLLBACK includes multi-service + updater freeze guidance.
      - LOCAL/PROD runbooks document ESO as mandatory and describe `make dev-vault` flow; no fallback to Opaque secrets.
    notes: Avoid duplicating upstream docs; link and show minimal verified commands.

16. id: T15
    name: Bootstrap — ESO install and preflight
    description: Extend bootstrap to install ESO via OLM Subscription and add preflight checks for ESO CRDs/CSV readiness before applying ExternalSecrets.
    why: Ensures clusters are reconciliation-ready and avoids timing issues when applying ESO resources.
    dependencies: [T6]
    acceptance_criteria:
      - scripts/bootstrap.sh: creates Subscription, waits for CSV InstallSucceeded, verifies CRDs present.
      - Subsequent chart installs (eso-vault-examples) succeed repeatably on fresh clusters.
    notes: Keep operator channels pinned in bootstrap-operators or in docs per T12.
