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
   name: Secrets — Enforce Vault via VSO + VCO (Platform)
   description: Standardize on HashiCorp Vault Secrets Operator (VSO) for runtime secret delivery and Red Hat COP Vault Config Operator (VCO) for Vault control-plane configuration across all envs. Remove ESO usage and avoid ad-hoc `oc create secret` flows entirely.
   why: Uses OpenShift-certified operators, unlocks dynamic secrets/rotation, reduces layers, and keeps Vault config declarative under Git.
   dependencies: [T0]
   status: in-progress (operator Subscriptions + bootstrap waits merged; charts/cutover pending)
   acceptance_criteria:
      - scripts/bootstrap.sh installs pinned Subscriptions for VSO (`secrets.hashicorp.com`) and VCO (`redhatcop.redhat.io`), waits for CSV InstallSucceeded, and verifies CRDs present (e.g., `vaultconnections.secrets.hashicorp.com`, `kubernetesauthengineconfigs.redhatcop.redhat.io`).
      - New charts exist: `charts/vault-runtime/` (VSO: `VaultConnection`, `VaultAuth`, `VaultStaticSecret`/`VaultDynamicSecret`) and `charts/vault-config/` (VCO: mounts, auth backends/roles, policies) rendered by default for all envs. `charts/eso-vault-examples/` is deprecated.
      - All platform creds (argocd-image-updater token, quay dockerconfig, github webhook) are delivered by VSO-managed Kubernetes Secrets (names unchanged for consumers).
      - Make targets and docs prohibit direct `oc create secret`; local/dev seeding happens by writing to Vault and reconciling via VSO/VCO.
      - `make validate` renders VSO/VCO resources and passes kubeconform (ignoring CRDs as needed) for local|sno|prod.
      - A version matrix (docs/CONVENTIONS.md or new `docs/OPERATOR-VERSIONS.md`) enumerates exact operator versions/CSVs to use (GitOps 1.18.x, Pipelines 1.20.x, VSO v1.0.1, VCO v0.8.34) and links to the matching official documentation.
      - Umbrella gating exists to enable VSO/VCO per env without enabling ESO concurrently; avoids dual-writer risk during migration.
   notes: References — VSO: https://github.com/hashicorp/vault-secrets-operator (CRDs: VaultConnection, VaultAuth, VaultStaticSecret, VaultDynamicSecret); VCO: https://github.com/redhat-cop/vault-config-operator (CRDs include KubernetesAuthEngineConfig/Role, SecretEngineMount, Policy). Subscriptions/CRD waits added in PR #54; gated umbrella apps added in PR #57.

8. id: T7
   name: Secrets — toy-service via VSO
   description: Secret-backed env injection for toy-service (`backend.secret.*`, `backend.env`) using VSO. Define a `VaultStaticSecret` (or `VaultDynamicSecret` where applicable) that writes to a Kubernetes Secret named `toy-service-config` across all envs.
   why: Demonstrates end-to-end secret propagation with VSO, keeping Secret names stable for the Deployment while enabling rotation.
   dependencies: [T6]
   status: planned (migrates from ESO)
   acceptance_criteria:
     - Deployment consumes env exclusively from the VSO-managed Secret; no plain env defaults for sensitive data.
     - VSO resources render by default and reconcile `toy-service-config` from the documented Vault path/keys.
     - `make validate` passes without flags; docs show local seeding via `make dev-vault` and VSO/VCO CRs.
   notes: Prefer `VaultStaticSecret` for KV; optionally add a `VaultDynamicSecret` example (DB creds) to showcase rotation semantics.

9. id: T8
   name: Secrets — toy-web via VSO
   description: Mirror T7 for frontend (`frontend.secret.*`, `frontend.env`) with a `VaultStaticSecret` that writes to `toy-web-config` for sensitive runtime configuration.
   why: Completes the secrets story for frontend with VSO.
   dependencies: [T7]
   status: planned (mirrors toy-service migration)
   acceptance_criteria:
     - Deployment consumes sensitive env solely via VSO-managed Secret; non-sensitive values may use ConfigMap.
     - VSO resources render by default and validate in `make validate` for all envs.
   notes: Keep non-sensitive params in ConfigMap where appropriate; no direct env literals for secrets.

10. id: T9
    name: Local Vault Automation (ENV=local)
    description: Replace Opaque secret fallback with automated local Vault + VCO/VSO flow. Provide a `make dev-vault` target that deploys a dev Vault, seeds required paths, applies VCO CRs (auth backends/roles, policies), and reconciles VSO resources for local.
    why: Preserves GitOps discipline locally; removes manual CLI secret creation and keeps parity with sno/prod.
    dependencies: [T6, T7, T8]
    status: planned (local parity after VSO migration)
    acceptance_criteria:
      - `make dev-vault` deploys a dev Vault (ephemeral) or connects to a configured Vault, writes sample values to `gitops/data/...` paths.
      - scripts/bootstrap.sh detects/installs VSO + VCO in local and applies minimal `VaultConnection`/`VaultAuth` and VCO `KubernetesAuthEngineConfig/Role`.
      - Pods in `bitiq-local` show env vars present via /internal/config; no Opaque secret creation path remains in docs.
    notes: Dev Vault must be clearly marked non-production; provide cleanup command.

11. id: T10
    name: Triggers & Registry Auth Hardening (VSO-only)
    description: EventListener and Tekton SA must consume secrets only via VSO-managed Kubernetes Secrets; replace `make quay-secret` with Vault seeding + VSO reconciliation. Document resolver versions.
    why: Eliminates manual secret management in CI; aligns with enforced Vault/VSO policy.
    dependencies: [T6]
    status: planned (post-VSO cutover)
    acceptance_criteria:
      - EventListener references a VSO-managed GitHub secret; pipeline SA mounts a VSO-managed Quay dockerconfig.
      - Provide `make dev-vault` seeding for required CI creds; remove direct `oc create secret` helper.
      - Docs updated with Pipelines 1.20 links and verification steps.
    notes: `triggers.createSecret` default remains false; all secrets sourced via Vault.

12. id: T11
    name: ApplicationSet Guardrails & Lint
    description: Tighten ApplicationSet generator scoping to intended envs/clusters; ensure `ignoreMissingValueFiles: true` and env parameterization are consistent; add lint/static checks.
    why: Prevents unintended app generation and keeps env overlays predictable.
    dependencies: [T0]
    status: planned
    acceptance_criteria:
      - ApplicationSet values include explicit env filters and correct param wiring for baseDomain/appNamespace/platforms/fsGroup.
      - `make validate` renders each env without missing values; conftest/policy checks (if present) pass.
    notes: Aligns with GitOps 1.18 usage patterns for ApplicationSets.

13. id: T12
    name: Operator Channels & Upgrade Guardrails
    description: Re-affirm pinned operator channels and require PR notes + maintainer approval before changing; add release notes links. Include VSO and VCO channels.
    why: Avoids accidental upgrades diverging from tested docs and runbooks.
    dependencies: [T0]
    status: in-progress (matrix doc + README/AGENTS links merged; runbook links pending)
    acceptance_criteria:
      - bootstrap-operators values document channels with links to GitOps 1.18, Pipelines 1.20, VSO, and VCO release notes.
      - A committed operator version matrix lists the exact starting CSV / semantic version per operator and references the precise documentation set to follow during upgrades (e.g., GitOps 1.18.z install guide, VSO v1.0.1 docs).
      - AGENTS.md/README state the approval requirement; CI remains green after edits.
    notes: GitOps 1.18 release notes: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/release_notes/; Pipelines 1.20 release notes: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20/html/release_notes/; VSO: https://github.com/hashicorp/vault-secrets-operator/releases; VCO: https://github.com/redhat-cop/vault-config-operator/releases

14. id: T13
    name: Validation Pipeline — VSO/VCO & AppSet Coverage
    description: Expand `make validate` to always render/validate VSO and VCO resources (no flag) and sanity-check ApplicationSet per env. Update conftest policies to allowlist VSO/VCO CRDs while continuing to forbid Kubernetes Secret manifests in Git.
    why: Enforced VSO/VCO means validation and policy must cover them by default.
    dependencies: [T6]
    status: in-progress (policy text updated; validation renders VSO/VCO)
    acceptance_criteria:
      - `make validate` renders VSO/VCO resources with repo values and passes kubeconform (ignoring CRDs as needed).
      - Conftest/regos updated to allow CRD groups `secrets.hashicorp.com` and `redhatcop.redhat.io` and to keep rejecting `apiVersion: v1`, `kind: Secret` in repo manifests.
      - Validation outputs show pass/fail clearly for each chart and env.
    notes: Keep runtime short; parallelize if needed.

15. id: T14
    name: Documentation Cross-links & Examples
    description: Update README and runbooks with explicit links to GitOps 1.18 and Pipelines 1.20 install/config, include enforced VSO/VCO + Vault usage, and local Vault automation.
    why: Keeps docs version-correct and reduces onboarding friction under the new policy.
    dependencies: [T1, T2, T3, T10]
    status: in-progress (README/AGENTS updated; runbooks pending)
    acceptance_criteria:
      - README/runbooks reference correct doc versions; ROLLBACK includes multi-service + updater freeze guidance.
      - LOCAL/PROD runbooks document VSO/VCO as mandatory and describe `make dev-vault` flow; no fallback to Opaque secrets.
    notes: Avoid duplicating upstream docs; link and show minimal verified commands.

16. id: T15
    name: Bootstrap — VSO/VCO install and preflight
    description: Extend bootstrap to install VSO and VCO via OLM Subscriptions and add preflight checks for their CRDs/CSV readiness before applying VSO/VCO resources.
    why: Ensures clusters are reconciliation-ready and avoids timing issues when applying secrets/config resources.
    dependencies: [T6]
    status: complete (subscriptions, waits merged in PR #54)
    acceptance_criteria:
      - scripts/bootstrap.sh: creates Subscriptions, waits for CSV InstallSucceeded, verifies VSO/VCO CRDs present.
      - Subsequent chart installs (`vault-runtime`, `vault-config`) succeed repeatably on fresh clusters.
    notes: Keep operator channels pinned in bootstrap-operators or in docs per T12.

17. id: T16
    name: Secret Reload Strategy (opt-in)
    description: Decide and implement a strategy for reacting to Kubernetes Secret updates produced by VSO (e.g., Stakater Reloader operator, or checksum annotations triggering rollouts). Apply minimally to toy apps and document guidance for production services.
    why: Secrets rotate without guaranteed pod reload; having a predictable pattern prevents stale credentials.
    dependencies: [T6, T7, T8]
    status: planned (design decision required)
    acceptance_criteria:
      - Documented choice with trade-offs; implementation for toy-service and toy-web verified (pods roll on Secret change without manual intervention).
      - If using checksum pattern, templates include annotations sourced from the VSO-managed Secret metadata/version where feasible; otherwise, reloader operator is installed and scoped.
      - Rollback guidance included (disable reloader or remove annotations) without service disruption.
    notes: Prefer least privilege and opt-in per Deployment; avoid global restarts.

18. id: T17
    name: ESO Decommission & Migration Tracking
    description: Fully remove ESO usage and artifacts after VSO/VCO are in place. Provide a mapping of each ExternalSecret/ClusterSecretStore to the corresponding VSO/VCO resources, and delete/deprecate `charts/eso-vault-examples/`.
    why: Avoids dual-writer risks and reduces operator footprint.
    dependencies: [T6, T7, T8, T9, T10, T13, T15]
    status: planned (execute after VSO rollout)
    acceptance_criteria:
      - A migration table exists in docs (ExternalSecret → VaultStaticSecret/VaultDynamicSecret; ClusterSecretStore → VaultConnection/VaultAuth). Secret consumer names remain unchanged.
      - ESO CRs are removed from the repo; the namespace(s) no longer contain ExternalSecrets for these apps; Argo reports Healthy/Synced post-cutover.
      - The umbrella disables `eso-vault-examples` when `vault-runtime` is enabled for a given env to prevent dual writers.
      - CI and local validation pass with only VSO/VCO resources.
    notes: Keep a rollback branch with ESO resources for emergency reversion; do not run ESO and VSO against the same Secret concurrently.

19. id: T18
    name: Operator Version Matrix & Doc Alignment
    description: Author and maintain a single source of truth for operator versions (GitOps 1.18.x, Pipelines 1.20.x, VSO v1.0.1, VCO v0.8.34) including their CSV names, catalog channels, support statements, and authoritative documentation links.
    why: Ensures everyone follows the correct install/upgrade guidance and avoids mixing docs across incompatible operator versions.
    dependencies: [T6, T12, T15]
    status: in-progress (matrix merged in PR #53; runbook links outstanding)
    acceptance_criteria:
      - `docs/OPERATOR-VERSIONS.md` (or an agreed existing doc) lists: operator name, channel, startingCSV/version, Red Hat/HashiCorp documentation URL, and upgrade cadence expectations.
      - README, AGENTS.md, and runbooks link to the matrix when referencing operator setup steps.
      - Process documented for updating the matrix during upgrades (new PR checklist item referencing T12 guardrails).
    notes: Confirm versions against OperatorHub for OCP 4.19 before publishing; include a sanity command (`oc get csv -n <ns>`) to verify deployed versions post-bootstrap.
