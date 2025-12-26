# Plan: ENV=prod parity with ENV=local (AWS OCP)

Objective: make the prod environment behave like the stable local stack (Argo CD + Tekton + sample apps + Vault-managed secrets) without leaking secrets. Tasks are ordered to unblock reconciliation first, then feature parity, then validation. Each task includes why it’s needed and the done condition.

## 1) Baseline + env wiring
- Why: Ensure the ApplicationSet renders the prod umbrella with the right cluster/baseDomain inputs so downstream fixes land in the right place.
- Actions:
  - Run `ENV=prod BASE_DOMAIN=<apps domain> ./scripts/prod-preflight.sh` and fix blockers.
  - Confirm `charts/argocd-apps/values.yaml` `prod` block matches the in-cluster model (`clusterServer=https://kubernetes.default.svc`, `appNamespace=bitiq-prod`, `baseDomain=<apps domain>`). Keep `envFilter=prod` in bootstrap arguments.
  - Decide fsGroup for Tekton (`envs[2].tektonFsGroup`); set via `TEKTON_FSGROUP` or commit an override if auto-detection fails on AWS.
- Done when: preflight passes and `helm template charts/argocd-apps` for prod shows expected cluster/baseDomain/tektonFsGroup values.

## 2) Vault/VSO/VCO correctness for prod
- Why: Current VCO defaults define a `Policy` named `gitops-local`; the prod role uses `gitops-prod`, so policy/role mismatches will block secrets and application health.
- Actions:
  - Update the prod Application (via `charts/bitiq-umbrella/templates/app-vault-operators.yaml` values block) to pass the env-specific policy name into the `policies` list so VCO creates `Policy gitops-prod` alongside `KubernetesAuthEngineRole gitops-prod`.
  - Ensure the prod Vault endpoints/role names are real (`vaultRuntimeAddress`, `vaultConfigAddress`, `roleName/policyName`), or parameterize them for the AWS Vault deployment.
  - If Vault is external, document any CA/SSL settings needed for VSO/VCO connectivity.
- Done when: `helm template charts/vault-config` as rendered for prod shows a Policy named `gitops-prod` and the role references the same policy; VSO/VCO Application values use the real Vault address.

## 3) Seed required secrets in Vault (no K8s ad-hoc secrets)
- Why: Without seeded data VSO will create empty Secrets and apps will fail. Prod must stay Vault-first.
- Actions:
  - Prepare Vault KV entries (KV v2 under `gitops/data/...`): `argocd/image-updater.token`, `registry/quay.dockerconfigjson`, `github/webhook.token`, `github/gitops-repo.{url,username,password}`, `services/toy-service/config.FAKE_SECRET`, `services/toy-web/config.API_BASE_URL`, plus any nostr/Route53 credentials if those workloads/Route53 are enabled.
  - Note: route53 credentials keys must match `cert-manager/route53` path if cert-manager DNS-01 is enabled.
  - Add a short checklist to `docs/PROD-SECRETS.md` (prod section) to reflect any new paths introduced by tasks below.
- Done when: Vault has the required keys and `vault-runtime-prod`/`vault-config-prod` render the matching `VaultStaticSecret`/roles for prod paths.

## 4) Route/domain parity for sample apps
- Why: `charts/toy-service/values-prod.yaml` hard-codes `svc-web.apps.prod.example` for the extra Route; BASE_DOMAIN overrides won’t fix this, breaking `/echo` in real prod.
- Actions:
  - Update the toy-service Route templating to derive the additional route host from `.Values.baseDomain` when `host` is empty; then set `host: ""` in values-prod to pick up the override automatically.
  - Ensure `baseDomain` is required for prod and passed via bootstrap (`BASE_DOMAIN` env).
- Done when: Rendering prod with a custom `BASE_DOMAIN` yields toy-service Routes on `svc-api.<baseDomain>` and extra route `svc-web.<baseDomain>/echo` without hand-editing values.

## 5) Align service overlays (enablement + values-prod)
- Why: Local enables strfry, Couchbase, cert-manager, nginx-sites, nostr workloads, signet-landing, ollama, etc.; prod disables them and lacks `values-prod.yaml` overlays. Parity requires env-specific values and enablement toggles.
- Actions:
  - For each service enabled in local (strfry, couchbase + operator, cert-manager-config, nginx-sites, nostr-query, nostr-threads, nostr-thread-copier, nostouch, signet-landing, ollama if desired), add a sanitized `values-prod.yaml` with placeholders (no secrets/domains) and adjust defaults for prod (e.g., storage class names, persistence sizes, replica counts).
  - Flip the prod env flags in `charts/argocd-apps/values.yaml` to match the chosen set. Keep anything not ready disabled with rationale noted in the plan or comments.
  - Ensure any new secrets those charts expect are covered by VSO (extend `charts/vault-runtime/values.yaml` if needed).
- Done when: `helm template charts/bitiq-umbrella --set env=prod ...` renders Applications for the selected services with prod overlays present and no missing value files; disabled services are explicitly documented.

## 6) Operator lifecycle and TLS
- Why: Prod currently skips `bootstrapOperators` and `certManager`; local enables them. Without cert-manager Route53 creds, TLS/ACME flows will fail; operator channels must stay pinned for OCP 4.19.
- Actions:
  - Decide if prod should let Argo manage operators (`bootstrapOperators.enabled`) and cert-manager (`certManager.enabled`, `certManager.route53CredentialsEnabled`). If yes, enable flags and ensure the OLM channels in `charts/bootstrap-operators/values.yaml` stay pinned (gitops-1.18, pipelines-1.20, cert-manager stable-v1, VSO/VCO channels).
  - Provide/validate Route53 Vault data if DNS-01 is enabled; otherwise keep cert-manager off and document the choice.
  - If operators remain manual, add a note in `docs/PROD-RUNBOOK.md` clarifying the manual expectation for prod.
- Done when: Operator management strategy is explicit, chart flags reflect it, and TLS/Route53 requirements are documented or satisfied.

## 7) Pipeline parity and repo creds
- Why: Tekton needs writable PVCs and registry/git creds; local fsGroup defaults may not match AWS OCP UID ranges.
- Actions:
  - Set/verify `ciPipelines.fsGroup` for prod (either via bootstrap-detected `TEKTON_FSGROUP` or a committed override).
  - Ensure VSO delivers `quay-auth`, `github-webhook-secret`, and `gitops-repo-creds` into `openshift-pipelines`; link `quay-auth` to `pipeline` SA (`oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount`).
  - Confirm `ci-pipelines` chart values don’t hardcode local-only registry or webhook domains; adjust if needed for prod baseDomain/webhook ingress.
- Done when: Prod pipelines can run with correct fsGroup and secrets, and no local-only endpoints remain.

## 8) Image/tag parity and umbrella appVersion
- Why: Prod overlays use older tags than local; appVersion is still the older composite. Without updates, prod won’t reflect current builds.
- Actions:
  - Update `charts/toy-service/values-prod.yaml` and `charts/toy-web/values-prod.yaml` to the desired tags (match local or newer). Repeat for nostr-threads/nostouch if pinning for prod.
  - Run `scripts/compute-appversion.sh` (or `make verify-release`) to refresh `charts/bitiq-umbrella/Chart.yaml appVersion`.
- Done when: Prod values carry the intended tags and appVersion reflects the new mix.

## 9) Validation + smoke on AWS cluster
- Why: Confirms parity end-to-end.
- Actions:
  - Run `make lint template validate verify-release`.
  - On the AWS cluster: `ENV=prod BASE_DOMAIN=<apps domain> ./scripts/bootstrap.sh` (or rerun with SKIP_APP_WAIT if iterating), then `./scripts/prod-smoke.sh`.
  - Verify Argo Applications are Synced/Healthy, VSO/VCO resources exist, sample Routes return 200s, and image-updater logs show successful tag discovery (or write-back if new tags exist).
- Done when: CI-style checks pass and prod smoke succeeds with healthy apps and reconciled secrets.

Notes:
- Keep commits small and secrets out of Git. Use placeholders in `values-prod.yaml` and document required Vault keys alongside any new overlays.
- If any services are intentionally not brought to parity, leave flags disabled and record the rationale so future agents don’t guess. 
