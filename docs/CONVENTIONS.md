# GitOps Conventions

Authoritative conventions for repository naming, versioning, and environment overlays. Follow these when adding new services, charts, or automation.

## Image tags

- Grammar: `v<MAJOR.MINOR.PATCH>-commit.<SHORT_SHA>` (e.g., `v0.3.2-commit.7e9c1f2`).
- `SHORT_SHA` is 7+ characters for readability and uniqueness.
- Tekton computes the tag via `scripts/ci-pipelines/templates/pipeline.yaml` to ensure CI outputs the deterministic form on every build.
- Argo CD Image Updater is restricted to this grammar via `argocd-image-updater.argoproj.io/app.allow-tags`.
- When bumping values manually, always keep the tag shape to preserve rollbacks and auditability.

## Composite `appVersion`

- Grammar: `<svcA>-vX.Y.Z-commit.<sha>_<svcB>-vA.B.C-commit.<sha>`; entries are sorted lexicographically by service name.
- Primary location: `charts/bitiq-umbrella/Chart.yaml`.
- Generate/update by running:

  ```bash
  make compute-appversion ENV=local        # or sno|prod
  ```

- Behind the scenes `scripts/compute-appversion.sh` inspects `values-<env>.yaml` for each chart in `CHARTS` (default `charts/toy-service charts/toy-web`).
- To include additional services, extend `CHARTS` when running the script:

  ```bash
  CHARTS="charts/toy-service charts/toy-web charts/another-svc" make compute-appversion ENV=sno
  ```

- Keep the umbrella chart’s `appVersion` in sync with the image tags committed in the same change.
- Before merging, run `make verify-release` to ensure `appVersion` matches the per-env image tags and that all tags follow the deterministic grammar.

## Values file precedence

- File order for each chart (and Argo CD `Application` helm source):
  1. `values.yaml` (or the chart’s `values-common.yaml`)
  2. `values-<env>.yaml`
  3. `values-<env>-local.yaml`
- Argo CD relies on `ignoreMissingValueFiles: true`, so optional overlays can be omitted without breaking sync.
- When testing locally:

  ```bash
  export ENV=local
  helm template charts/bitiq-umbrella \
    -f charts/bitiq-umbrella/values-common.yaml \
    -f charts/toy-service/values-${ENV}.yaml \
    -f charts/toy-web/values-${ENV}.yaml >/dev/null
  ```

## Namespace and app naming

- Namespace convention: `bitiq-<env>`.
- Umbrella Argo CD Application: `bitiq-umbrella-<env>`.
- Child Argo CD Applications include the env suffix (e.g., `ci-pipelines-<env>`, `image-updater-<env>`, `toy-service-<env>`, `toy-web-<env>`).
- Add the label `bitiq.io/env=<env>` to namespaces and top-level workloads for fleet queries.

## Rollback recipe

1. Identify the Git commit that introduced the undesired change (check `values-<env>.yaml` and `Chart.yaml` history).
2. `git revert <commit>` (or revert PR) and push to the tracked branch.
3. (Optional) Run `make compute-appversion ENV=<env>` if you need to recompute the composite after manual edits.
4. `argocd app sync bitiq-umbrella-<env>` (or wait for auto-sync) and verify the composite `appVersion` matches expectations in the Argo UI.
5. Confirm the restored image tags follow the deterministic grammar.

Keep this file updated whenever conventions evolve.
