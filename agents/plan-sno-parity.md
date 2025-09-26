# ENV=sno Parity Execution Plan (for Codex Agents)

Purpose: Bring ENV=sno to parity with ENV=local across Argo CD, Tekton, and sample app flows, with minimal, scoped changes and clear validation.

## Branching & Commit
- Branch: docs/sno-parity-plan
- Commit style: Conventional Commits
- PR scope: one purpose per PR; keep changes small and verifiable

## Implementation Order
1) Align SNO cluster destination
2) Wire BASE_DOMAIN through bootstrap/ApplicationSet
3) Gate Tekton image namespace creation
4) Make Tekton fsGroup optional/safe
5) Ensure required secrets (webhook + image-updater)
6) Validate rendering and smoke checks
7) Document SNO runbook notes

---

## 1) Align SNO cluster destination
Objective: Ensure the umbrella Application targets the correct cluster when ENV=sno.

- Files to update:
  - charts/argocd-apps/values.yaml
- Change:
  - If Argo CD runs in the same SNO cluster, set `envs[].clusterServer` for `sno` to `https://kubernetes.default.svc`.
  - If using a central Argo CD to manage an external SNO, leave as actual API URL but ensure the SNO cluster is registered in Argo CD prior to sync.
- Steps:
  - Edit `charts/argocd-apps/values.yaml` sno item.
  - Commit: `fix(argocd-apps): set sno clusterServer to in-cluster or document external cluster prereq`
- Validation:
  - `helm template charts/argocd-apps --set envFilter=sno | rg 'destination:.*server:' -n`
  - Confirm destination server is correct for your topology.

## 2) Wire BASE_DOMAIN through bootstrap/ApplicationSet
Objective: Ensure sample app Routes use the real SNO base domain without manual edits in chart values.

- Options (choose one):
  A) Pass a runtime override from bootstrap
     - In `scripts/bootstrap.sh`, add `--set-string envs[?].baseDomain="$BASE_DOMAIN"` when `ENV=sno`.
       - Preferred: avoid hard-coded index by matching `name=sno` via `--set-json`/value file; simple approach may target index if stable.
  B) Add `baseDomainOverride` to `charts/argocd-apps/values.yaml` and in the ApplicationSet template use `default .Values.baseDomainOverride .baseDomain`.
     - Then in bootstrap: `--set-string baseDomainOverride="$BASE_DOMAIN"`.
  C) Add an env-specific overlay file (e.g., `charts/argocd-apps/values-sno-local.yaml`) and have bootstrap pass `-f` when ENV=sno.

- Files to update:
  - scripts/bootstrap.sh (Option A or C)
  - charts/argocd-apps/templates/applicationset-umbrella.yaml (Option B)
  - charts/argocd-apps/values.yaml (Option B default field)
- Commit:
  - `feat(bootstrap): plumb BASE_DOMAIN into ApplicationSet for sno`
  - `feat(argocd-apps): support baseDomainOverride (optional)`
- Validation:
  - `helm template charts/argocd-apps --set envFilter=sno --set baseDomainOverride=apps.<your-sno-domain> | rg 'baseDomain'`
  - After sync, sample Routes: `svc-api.${BASE_DOMAIN}`, `svc-web.${BASE_DOMAIN}`.

## 3) Gate Tekton image namespace creation
Objective: Avoid creating stray Kubernetes Namespaces for external registry orgs (e.g., `paulcapestany`).

- Files to update:
  - charts/ci-pipelines/values.yaml
  - charts/ci-pipelines/templates/namespace-target.yaml
- Change:
  - Add `createImageNamespaces: false` (default).
  - Wrap `namespace-target.yaml` with `{{- if .Values.createImageNamespaces }}` … `{{- end }}`.
- Commit: `feat(ci-pipelines): gate creation of image namespaces (default off)`
- Validation:
  - `helm template charts/ci-pipelines | rg '^kind: Namespace' -n` → none by default.
  - Set `--set createImageNamespaces=true` to test behavior.

## 4) Make Tekton fsGroup optional/safe
Objective: Reduce cluster-specific UID/GID coupling that can break on SNO.

- Files to update:
  - charts/ci-pipelines/values.yaml
  - charts/bitiq-umbrella/values-common.yaml
  - charts/ci-pipelines/templates/triggers.yaml (uses `.Values.fsGroup` in podTemplate via TriggerTemplate)
  - charts/ci-pipelines/templates/pipelinerun-example.yaml
- Change:
  - Default `fsGroup: ""` (unset). Only apply in templates when non-empty.
  - In templates where `fsGroup` is used, guard with `{{- if $pipelineFsGroup }}` blocks or set podTemplate only when set.
- Commit: `fix(ci-pipelines): make fsGroup optional; rely on SCC defaults when unset`
- Validation:
  - `helm template charts/ci-pipelines | rg 'fsGroup' -n` → absent by default.
  - Run Pipeline on SNO; ensure Tasks complete without mount permission errors.

## 5) Ensure required secrets (webhook + image-updater)
Objective: Make it clear and reproducible to provision secrets on SNO.

- GitHub webhook Secret in `openshift-pipelines`:
  - Option 1: Set `triggers.createSecret=true` and provide `triggers.secretToken` in a secure way (not committed).
  - Option 2: Create via `oc`: `oc -n openshift-pipelines create secret generic github-webhook-secret --from-literal=secretToken=<token>`.
- Image Updater token Secret in `openshift-gitops`:
  - Use: `ARGOCD_TOKEN=<token> make image-updater-secret`.
- Commit (docs only): `docs(ci): add SNO secret setup notes`
- Validation:
  - EventListener responds 200 to webhook with valid signature.
  - Image Updater logs show successful ArgoCD API auth and write-back.

## 6) Validate rendering and smoke checks
Objective: Keep local and CI validations green for sno.

- Commands:
  - `make template` (includes local, sno, prod)
  - `make validate`
  - Optional cluster smoke: `make smoke ENV=sno BOOTSTRAP=true BASE_DOMAIN=apps.<your-sno-domain>`
- Acceptance:
  - No template/schema errors for sno.
  - Umbrella app `bitiq-umbrella-sno` becomes Healthy/Synced; sample Routes resolve.

## 7) Document SNO runbook notes
Objective: Add concise, SNO-focused instructions.

- Files to update:
  - README.md (SNO notes section)
- Content:
  - Export `ENV=sno` and `BASE_DOMAIN=apps.<domain>`; run `scripts/bootstrap.sh`.
  - Clarify destination model (in-cluster vs central Argo CD) and corresponding `clusterServer` value.
  - Secret provisioning one-liners (webhook + image-updater).
  - Pointer to `make smoke` for verification.
- Commit: `docs(readme): add SNO runbook notes`

---

## Notes & Risks
- If using external (central) Argo CD, ensure the SNO cluster is registered (`argocd cluster add ...`) before syncing ApplicationSet for ENV=sno.
- README note about local frontend image updates may be stale; verify `enableFrontendImageUpdate` values vs desired behavior.
- Do not commit secrets; use manual creation or an opt-in chart flag with env-injected values.

## Definition of Done
- ApplicationSet for sno renders correct destination server and baseDomain.
- Sample app Routes use `${BASE_DOMAIN}` and serve traffic.
- Tekton PipelineRun on sno builds/pushes successfully; webhook trigger verified.
- Image Updater detects tags and writes back to `charts/bitiq-sample-app/values-sno.yaml`.
- No unintended Namespaces created by ci-pipelines chart.
- All validations pass: `make template`, `make validate`, and optional `make smoke`.
