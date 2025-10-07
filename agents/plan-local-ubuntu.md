# ENV=local on Remote Ubuntu (Agent‑Actionable Plan)

Purpose: Enable a full ENV=local end‑to‑end workflow (Argo CD + Tekton + Image Updater + sample app) on a remote Ubuntu server, using OpenShift Local (CRC). Plan is split into small, verifiable PRs aligned with AGENTS.md Golden Rules.

## Current State (repo readiness)
- ENV=local is designed for OpenShift Local (CRC). Defaults (Routes, domains, namespaces) are wired and bootstrap works via `scripts/bootstrap.sh`.
- Inbound GitHub webhooks for CRC are documented via port‑forward + dynamic DNS (preferred on remote servers) or ngrok/cloudflared as an alternative (docs/LOCAL-CI-CD.md).
- Image Updater platform filter is passed from the ApplicationSet to the umbrella chart. Today `local.platforms` defaults to `linux/arm64` (charts/argocd-apps/values.yaml:18), which mismatches typical Ubuntu servers (`linux/amd64`).
- Mac‑focused setup docs exist; a Linux/Ubuntu path is not consolidated. Bootstrap doesn’t expose a simple knob to override the local platform.

Conclusion: The stack largely works, but running ENV=local on a remote Ubuntu server is not frictionless due to the default `linux/arm64` platform and lack of an Ubuntu runbook. Minimal chart + docs + script tweaks will make it turnkey.

## Branching & Commit
- Create focused branches per task (e.g., `docs/local-ubuntu-runbook`, `fix(argocd-apps)-local-amd64`, `feat(scripts)-platform-override`).
- Use Conventional Commits with scopes (charts, scripts, docs).
- Validate locally before PR: `make lint`, `make hu`, `make template`, `make validate`.

## Work Plan (small, verifiable PRs)

1) Flip local default platform to linux/amd64 (simple, low risk)
- Change: Set `envs[].name=local.platforms` to `linux/amd64`.
- Files: charts/argocd-apps/values.yaml
- Commit: fix(charts): default ENV=local platforms to linux/amd64
- Acceptance:
  - `helm template charts/argocd-apps --set envFilter=local` shows `imageUpdater.platforms: linux/amd64` in the rendered umbrella Application params.
  - `make template` and `make validate` pass.

2) Add Ubuntu runbook for CRC + remote e2e
- Change: New Linux‑specific runbook with copy/paste steps to install CRC, `oc`, `helm`, `argocd` CLIs on Ubuntu; enable KVM/libvirt; bootstrap ENV=local; set up webhook exposure via dynamic DNS (port‑forward with `--address 0.0.0.0`) or ngrok on the server; basic smoke checks. Include SSH tunnel tips (optional) and notes on apps‑crc.testing being internal to CRC.
- Files: docs/LOCAL-RUNBOOK-UBUNTU.md
- Commit: docs(local): add Ubuntu (CRC) runbook for ENV=local
- Acceptance:
  - Steps are self‑contained for Ubuntu 22.04/24.04.
  - Links to Red Hat CRC docs and official CLI install pages.

3) Expose platform override in bootstrap (optional but helpful)
- Change: Allow overriding the Image Updater platform for the selected ENV during bootstrap.
- Implementation:
  - Add env var `PLATFORMS_OVERRIDE` to `scripts/bootstrap.sh`. When set and `ENV=local`, append: `--set-string envs[0].platforms="$PLATFORMS_OVERRIDE"` to the `helm upgrade` for `charts/argocd-apps`.
  - Guard with a comment noting the index relies on current env ordering (local,sno,prod). Keep small and avoid chart changes.
- Files: scripts/bootstrap.sh
- Commit: feat(scripts): add PLATFORMS_OVERRIDE for ENV=local in bootstrap
- Acceptance:
  - `PLATFORMS_OVERRIDE=linux/arm64 ENV=local ./scripts/bootstrap.sh` renders `imageUpdater.platforms: linux/arm64` for the umbrella app.
  - Default behavior remains `linux/amd64` after Task 1.

4) Update local CI/CD doc with remote usage callouts
- Change: Add a short “Remote server” section to docs/LOCAL-CI-CD.md with:
- How to run `oc port-forward --address 0.0.0.0` on the server with dynamic DNS (or use `ngrok`), and validate GitHub webhook deliveries.
  - Reminder that `apps-crc.testing` is only reachable from the CRC host (use curl on the server or SSH tunnel to test Routes).
- Files: docs/LOCAL-CI-CD.md
- Commit: docs(local): add remote server webhook and access notes
- Acceptance: The notes are concise, actionable, and do not duplicate the new Ubuntu runbook.

5) README pointers
- Change: Add a brief Linux/Ubuntu note and link to the new runbook; clarify default platform and how to override via `PLATFORMS_OVERRIDE`.
- Files: README.md
- Commit: docs(readme): link Ubuntu runbook and platform override tip
- Acceptance: Quick start remains unchanged for macOS/CRC; Linux path is discoverable.

## Optional Follow‑ups (defer unless needed)
- Auto‑detect cluster arch in bootstrap (instead of PLATFORMS_OVERRIDE):
  - Detect via `oc get nodes -o jsonpath='{.items[0].status.nodeInfo.architecture}'` and set platforms accordingly.
  - Safer alternative: introduce `platformOverride` in the argocd‑apps chart and use it via `coalesce` in the template to avoid array indexing.
  - Scope PR as: feat(charts): support platformOverride in argocd‑apps; feat(scripts): detect cluster arch for ENV=local.

## Acceptance Criteria (end‑to‑end on Ubuntu)
- On Ubuntu 22.04/24.04 with virtualization enabled, a user can:
  - Install CRC + CLIs per docs/LOCAL-RUNBOOK-UBUNTU.md.
  - Run `ENV=local ./scripts/bootstrap.sh` and see `bitiq-umbrella-local` Healthy/Synced in Argo CD.
  - Configure repo creds and Image Updater token; push a commit and trigger a Tekton PipelineRun via dynamic DNS + port‑forward (or ngrok).
  - Image Updater detects new tags and writes back to `charts/bitiq-sample-app/values-local.yaml`.
  - Routes function from the server (curl to `svc-api.apps-crc.testing/healthz`).

## Guardrails & Notes
- Do not change operator channels without explicit approval.
- Keep secrets out of Git; use the existing `make image-updater-secret`, `make tekton-setup` flows.
- Validate charts locally (`make validate`) and keep CI green.
- Prefer small PRs with clear scopes per the plan above.
