# Signet Signup Service Plan

Plan now gates signup work behind extracting the current signet.ing static site into its own app repo and re-integrating it via GitOps; only after that baseline is healthy do we add signup functionality.

1. id: S0  
   name: Landing Repo Extraction  
   description: Carve the existing signet.ing landing assets (currently under signet-trailer/) into a dedicated app repo under github.com/signeting with build instructions, license, and README. Preserve current behavior/assets and remove any GitOps-only bits from app code.  
   dependencies: []  
   status: complete (signeting/signet-landing created, initial import pushed)  
   acceptance_criteria: New repo (e.g., signeting/signet-landing) exists with clean history for the landing page, includes build steps and static output, no secrets or cluster manifests; old folder references are removed/archived here with pointers to the new repo.

2. id: S1  
   name: GitOps Re-integration (Static Only)  
   description: Wire the extracted landing repo into this GitOps flow as a static site (no signup): decide artifact shape (container image vs. tar seed), ensure Routes/Ingress/TLS for signet.ing continue to work, and align values with docs/CONVENTIONS.md.  
   dependencies: [S0]  
   status: complete (chart added; image quay.io/paulcapestany/signet-landing:0.1.2 multi-arch)  
   acceptance_criteria: Argo/umbrella config deploys the static site from the new repo/artifact; `make validate` passes; static content matches current production; no signup code or new secrets involved.  
   notes: GH Actions workflow disabled; Tekton pipeline + webhook now build/push signet-landing to Quay (public) using semver-safe tags `vX.Y.Z-commit.g<sha>`. Argo CD Image Updater write-back to `charts/signet-landing/values-common.yaml` is live and validated end-to-end via webhook-triggered release v0.1.9 (Quay → Image Updater git commit → Argo sync). GitHub webhook should target `http://k7501450.eero.online:18080` (EventListener); update if the tunnel/hostname changes.

3. id: S2  
   name: Baseline Validation  
   description: Smoke-test the re-integrated static site across envs (at least local) and confirm signet.ing serves the expected content with existing CDN/TLS behaviors.  
   dependencies: [S1]  
   status: complete  
   acceptance_criteria: Documented check showing the deployed site matches the pre-extraction version; no regressions in routes, assets, or SEO tags; ready to proceed to signup work.  
   notes: Local CRC smoke validated via `oc port-forward svc/signet-landing 18080:8080` + curl (HTTP 200, HTML served). Route remains `signet.ing`; image 0.1.2 running without pull secret (repo public).

4. id: S3  
   name: Signup Requirements & Architecture  
   description: Lock scope (fields collected, double opt-in, data retention/deletion, host/path, latency/SLOs, storage choice) and confirm the signup service lives in its own app repo with Argo delivery from this GitOps repo. Default recommendations: email (required) + optional name/referrer only; double opt-in; API served same-origin under `https://signet.ing/api/signup` to avoid CORS; Postgres for idempotent storage; SES as default mail provider (Postmark alternate); per-IP rate limiting + disposable-domain blocklist; secrets via Vault (VSO/VCO); tokens HMAC-signed with 24h TTL; p99 <300ms and 99.5% availability target.  
   dependencies: [S2]  
   status: pending  
   acceptance_criteria: Written decision doc covering form fields, opt-in policy, storage (Postgres vs S3 object), mail provider (SES/Postmark/etc.), domain/Route shape, and abuse posture; agreed owner for app repo + image registry; call out any net-new infra.

5. id: S4  
   name: Service Skeleton + Tests  
   description: Create a minimal signup API (POST /signup, GET/POST /confirm, healthz) with validation, idempotent responses, structured logs, and unit tests. Containerize with env-driven config and multi-stage build.  
   dependencies: [S3]  
   status: pending  
   acceptance_criteria: App repo contains API handlers, validation tests, Dockerfile, and Makefile/CI hooks; returns consistent 200/409/400 codes; no secrets or API keys checked in.

6. id: S5  
   name: Outbound Mail & Double Opt-in  
   description: Integrate mail provider via API key/SMTP, generate confirmation tokens, and send confirmation + success emails. Handle bounces/complaints minimally.  
   dependencies: [S4]  
   status: pending  
   acceptance_criteria: Configurable sender/domain; confirmation flow prevents storing unconfirmed emails; retry/backoff documented; webhook endpoints stubbed or noted if deferred.

7. id: S6  
   name: Persistence & Retention  
   description: Persist signups in first-party storage with encryption at rest and retention for unconfirmed entries. Provide schema/migrations and deletion hooks.  
   dependencies: [S4]  
   status: pending  
   acceptance_criteria: Schema (or object layout) checked in; migration/seed scripts exist; unconfirmed TTL policy documented; PII storage minimized (email + optional name only).

8. id: S7  
   name: Abuse Controls  
   description: Add rate limiting, disposable-domain blocklist, basic captcha/proof-of-work toggle, and idempotent “already subscribed” handling.  
   dependencies: [S4]  
   status: pending  
   acceptance_criteria: Limits configurable via env; tests cover rate limit + blocklist paths; optional captcha flag in config and Helm values; safe logging (no raw email in error logs).

9. id: S8  
   name: Vault/VSO/VCO Wiring  
   description: Define Vault KV path for signup secrets (mail API key, SMTP creds, DB URL, signing secret), policy, and auth role; project via VSO into the app namespace.  
   dependencies: [S3]  
   status: pending  
   acceptance_criteria: Vault path chosen (e.g., gitops/data/signet/signup); `charts/vault-config` updated if new policy/role needed; `charts/vault-runtime/templates/20-secrets-app.yaml` includes VaultStaticSecret for the app; values files reference only VSO-managed Secrets (no plaintext).

10. id: S9  
    name: Helm Chart & Env Overlays  
    description: Create `charts/signet-signup` with Deployment/Service/Route (or Ingress), readiness/liveness, resources, env wiring, optional ServiceMonitor, and toggles. Add `values-common.yaml` + env overlays (local/sno/prod).  
    dependencies: [S4, S8]  
    status: pending  
    acceptance_criteria: Chart renders cleanly via `make template` for all envs; image repo/tag follow docs/CONVENTIONS.md; hostnames configurable per env; no direct Secret manifests; resources and probes set.

11. id: S10  
    name: CI/CD & Image Promotion  
    description: Add in-cluster Tekton build/push for the signup service (and migrate signet-landing off GH Actions) publishing tagged images to Quay; wire optional Argo CD Image Updater tracking.  
    dependencies: [S4]  
    status: pending  
    acceptance_criteria: Tekton Pipeline/Trigger builds multi-arch images to Quay with Vault-sourced credentials; tags align with appVersion; signet-landing GH workflow disabled once Tekton path is live; if Image Updater is used, annotations/alias configured and tested; no manual pushes required.  
    notes: Signet-landing Tekton pipeline + Argo CD Image Updater are live and validated (v0.1.9 build via webhook -> Quay tag `v0.1.9-commit.g428cf12` -> Image Updater write-back -> Argo sync). Signup service pipeline still to be added; GitHub webhook for signet-landing may need external exposure beyond CRC for automatic triggers.

12. id: S11  
    name: Umbrella/AppSet Integration  
    description: Include the chart in `charts/bitiq-umbrella` and `charts/argocd-apps` per env with feature flagging and namespace selection.  
    dependencies: [S9, S10]  
    status: pending  
    acceptance_criteria: Umbrella values enable/disable per env; ApplicationSet renders correctly for local|sno|prod; `make validate` passes with the new app included.

13. id: S12  
    name: Frontend Hook-Up  
    description: Update signet.ing landing page to POST to the new endpoint (same origin preferred), handle success/error/already-registered states, and set CORS if needed. Keep page otherwise static.  
    dependencies: [S9, S11]  
    status: pending  
    acceptance_criteria: Form submits to the service; UX copy covers confirmation expectation; CORS config present only if cross-origin; static build/deploy path documented.

14. id: S13  
    name: Observability & Runbooks  
    description: Add logs/metrics dashboards, alerts on elevated 4xx/5xx and bounce/complaint rates, and document operational flows (Vault seeding, rotations, data deletion).  
    dependencies: [S5, S9]  
    status: pending  
    acceptance_criteria: Alerts configured (or documented if deferred); runbook updates in docs/ cover Vault seed paths, redeploy/rotation steps, and privacy/data deletion procedure; make validate remains green.
