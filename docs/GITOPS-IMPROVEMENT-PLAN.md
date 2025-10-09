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
   acceptance_criteria:
     - toy-service and toy-web repos contain no k8s manifests; issues/PRs add “Deployment via GitOps” links pointing here.
     - This repo’s README clearly states where runtime manifests live and how CI/Image Updater connects to microservice repos.
   notes: No relocation is needed given current repos; just document and link.

7. id: T6
   name: Secrets — ESO/Vault Enablement (Platform)
   description: Finalize `charts/eso-vault-examples` as an explicit opt-in for Argo token, Quay creds, and GitHub webhook secrets with Vault-backed ExternalSecrets.
   why: Production-grade, auditable secrets management aligned to ESO/Vault patterns.
   dependencies: [T0]
   acceptance_criteria:
     - PROD-SECRETS.md documents enablement flags and Vault paths; values reference ClusterSecretStore and refresh intervals; kubeconform validation passes when enabled.
     - Optional Tekton annotation (`tekton.dev/docker-0`) is documented for registry auth.
   notes: Pipelines 1.20 configuring: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20/html/configuring_openshift_pipelines/

8. id: T7
   name: Secrets — toy-service via ExternalSecret
   description: Add optional secret-backed env injection for toy-service (`backend.secret.*`, `backend.env`) and a matching ExternalSecret example (`toy-service-config`).
   why: Demonstrates end-to-end secrets propagation for backend runtime.
   dependencies: [T6]
   acceptance_criteria:
     - New values fields applied to Deployment env; ExternalSecret example produces `toy-service-config` with FAKE_SECRET (or similar) key.
     - Local template shows env wiring; `make validate` passes.
   notes: Keep disabled by default; document Vault KV path and keys.

9. id: T8
   name: Secrets — toy-web via ExternalSecret
   description: Mirror T7 for frontend (`frontend.secret.*`, `frontend.env`) with an example ExternalSecret (`toy-web-config`) for `API_BASE_URL`.
   why: Completes secrets story for frontend runtime configuration.
   dependencies: [T7]
   acceptance_criteria:
     - Values applied to Deployment env; ExternalSecret example renders and validates; `make validate` passes.
   notes: Consider ConfigMap for non-sensitive params; keep secret path for tokens.

10. id: T9
    name: Local Secrets Fallback (ENV=local)
    description: Add `make dev-secrets` to create local Opaque secrets for platform (updater token, webhook) and sample app (toy-service/web) without Vault.
    why: Enables end-to-end local testing without provisioning Vault.
    dependencies: [T7, T8]
    acceptance_criteria:
      - `make dev-secrets` manages: `argocd-image-updater-secret`, `github-webhook-secret`, `toy-service-config`, `toy-web-config` in correct namespaces.
      - LOCAL runbooks updated with usage and verification commands; pods show expected env vars.
    notes: Scope is local only; do not auto-create in SNO/prod.

11. id: T10
    name: Triggers & Registry Auth Hardening
    description: Ensure EventListener uses GitHub secret (ESO-managed when enabled) and Tekton SA links to Quay creds; document resolver versions.
    why: Secures CI triggers and ensures reliable image push per Pipelines 1.20 guidance.
    dependencies: [T6]
    acceptance_criteria:
      - TriggerBindings/TriggerTemplates per pipeline; EventListener references secret; `make quay-secret` remains valid.
      - Docs include Pipelines 1.20 links and verification steps.
    notes: Keep `triggers.createSecret=false` by default for safety.

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
    description: Expand `make validate` to optionally render/validate ESO chart (flag-driven) and sanity-check ApplicationSet per env.
    why: Catches misconfigurations early and keeps local/CI parity.
    dependencies: [T6]
    acceptance_criteria:
      - `VALIDATE_ESO=true make validate` renders ESO with sample values and passes kubeconform (ignoring CRDs as needed).
      - Validation outputs show pass/fail clearly for each chart and env.
    notes: Current script already handles CRDs; extend without slowing CI significantly.

15. id: T14
    name: Documentation Cross-links & Examples
    description: Update README and runbooks with explicit links to GitOps 1.18 and Pipelines 1.20 install/config, including updater pause usage and split-app guidance.
    why: Keeps docs version-correct and reduces onboarding friction.
    dependencies: [T1, T2, T3, T10]
    acceptance_criteria:
      - README/runbooks reference correct doc versions; ROLLBACK includes multi-service + updater freeze guidance.
      - LOCAL/PROD runbooks mention ESO enablement and local dev-secrets fallback.
    notes: Avoid duplicating upstream docs; link and show minimal verified commands.
