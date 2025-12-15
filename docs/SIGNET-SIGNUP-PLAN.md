# Signet Signup Service Plan

Structured tasks to add a first-party signup backend for signet.ing while keeping Vault/VSO/VCO and GitOps guardrails.

1. id: S0  
   name: Requirements & Architecture  
   description: Lock scope (fields collected, double opt-in yes/no, data retention/deletion, host/path, latency/SLOs, storage choice) and confirm the service lives in its own app repo with Argo delivery from this GitOps repo.  
   dependencies: []  
   status: pending  
   acceptance_criteria: Written decision doc covering form fields, opt-in policy, storage (Postgres vs S3 object), mail provider (SES/Postmark/etc.), domain/Route shape, and abuse posture; agreed owner for app repo + image registry; call out any net-new infra.

2. id: S1  
   name: Service Skeleton + Tests  
   description: Create a minimal signup API (POST /signup, GET/POST /confirm, healthz) with validation, idempotent responses, structured logs, and unit tests. Containerize with env-driven config and multi-stage build.  
   dependencies: [S0]  
   status: pending  
   acceptance_criteria: App repo contains API handlers, validation tests, Dockerfile, and Makefile/CI hooks; returns consistent 200/409/400 codes; no secrets or API keys checked in.

3. id: S2  
   name: Outbound Mail & Double Opt-in  
   description: Integrate mail provider via API key/SMTP, generate confirmation tokens, and send confirmation + success emails. Handle bounces/complaints minimally.  
   dependencies: [S1]  
   status: pending  
   acceptance_criteria: Configurable sender/domain; confirmation flow prevents storing unconfirmed emails; retry/backoff documented; webhook endpoints stubbed or noted if deferred.

4. id: S3  
   name: Persistence & Retention  
   description: Persist signups in first-party storage with encryption at rest and retention for unconfirmed entries. Provide schema/migrations and deletion hooks.  
   dependencies: [S1]  
   status: pending  
   acceptance_criteria: Schema (or object layout) checked in; migration/seed scripts exist; unconfirmed TTL policy documented; PII storage minimized (email + optional name only).

5. id: S4  
   name: Abuse Controls  
   description: Add rate limiting, disposable-domain blocklist, basic captcha/proof-of-work toggle, and idempotent “already subscribed” handling.  
   dependencies: [S1]  
   status: pending  
   acceptance_criteria: Limits configurable via env; tests cover rate limit + blocklist paths; optional captcha flag in config and Helm values; safe logging (no raw email in error logs).

6. id: S5  
   name: Vault/VSO/VCO Wiring  
   description: Define Vault KV path for signup secrets (mail API key, SMTP creds, DB URL, signing secret), policy, and auth role; project via VSO into the app namespace.  
   dependencies: [S0]  
   status: pending  
   acceptance_criteria: Vault path chosen (e.g., gitops/data/signet/signup); `charts/vault-config` updated if new policy/role needed; `charts/vault-runtime/templates/20-secrets-app.yaml` includes VaultStaticSecret for the app; values files reference only VSO-managed Secrets (no plaintext).

7. id: S6  
   name: Helm Chart & Env Overlays  
   description: Create `charts/signet-signup` with Deployment/Service/Route (or Ingress), readiness/liveness, resources, env wiring, optional ServiceMonitor, and toggles. Add `values-common.yaml` + env overlays (local/sno/prod).  
   dependencies: [S1, S5]  
   status: pending  
   acceptance_criteria: Chart renders cleanly via `make template` for all envs; image repo/tag follow docs/CONVENTIONS.md; hostnames configurable per env; no direct Secret manifests; resources and probes set.

8. id: S7  
   name: CI/CD & Image Promotion  
   description: Add build/push pipeline (Tekton here or GH Actions in app repo) publishing tagged images to the approved registry; wire optional Argo CD Image Updater tracking.  
   dependencies: [S1]  
   status: pending  
   acceptance_criteria: Pipeline builds/pushes tagged images; tags align with appVersion; if Image Updater is used, annotations/alias configured and tested; no manual pushes required.

9. id: S8  
   name: Umbrella/AppSet Integration  
   description: Include the chart in `charts/bitiq-umbrella` and `charts/argocd-apps` per env with feature flagging and namespace selection.  
   dependencies: [S6]  
   status: pending  
   acceptance_criteria: Umbrella values enable/disable per env; ApplicationSet renders correctly for local|sno|prod; `make validate` passes with the new app included.

10. id: S9  
    name: Frontend Hook-Up  
    description: Update signet.ing landing page to POST to the new endpoint (same origin preferred), handle success/error/already-registered states, and set CORS if needed. Keep page otherwise static.  
    dependencies: [S1, S6]  
    status: pending  
    acceptance_criteria: Form submits to the service; UX copy covers confirmation expectation; CORS config present only if cross-origin; static build/deploy path documented.

11. id: S10  
    name: Observability & Runbooks  
    description: Add logs/metrics dashboards, alerts on elevated 4xx/5xx and bounce/complaint rates, and document operational flows (Vault seeding, rotations, data deletion).  
    dependencies: [S2, S6]  
    status: pending  
    acceptance_criteria: Alerts configured (or documented if deferred); runbook updates in docs/ cover Vault seed paths, redeploy/rotation steps, and privacy/data deletion procedure; make validate remains green.
