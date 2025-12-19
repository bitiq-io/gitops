# End-to-End CI/CD Flow (All Services)

This describes the expected GitOps-first CI/CD path every service should follow (toy-service, toy-web, signet-landing, future signup service, etc.). Use this as the high-level contract; env-specific notes live in `docs/LOCAL-CI-CD.md` and runbooks.

## Responsibilities split
- App repos: only app code + Dockerfile + tests; no cluster manifests or secrets.
- GitOps repo (this repo): Helm charts, env overlays, Argo CD Applications, Image Updater annotations, Tekton pipeline/trigger definitions.

## Trigger path
1) Developer pushes to `main` and/or creates a semver tag (`vX.Y.Z`) in the app repo.  
2) GitHub webhook fires to the Tekton EventListener Route (local CRC: `http://k7501450.eero.online:18080` — update if the hostname/tunnel changes). Webhook secret comes from Vault (`gitops/data/github/webhook` via VSO).  
3) Tekton TriggerTemplate instantiates the build PipelineRun (repo filtered via CEL). No GitHub Actions are used for images.

## Build & tag
- Pipeline fetches full git history, computes deterministic tag `v<semver>-commit.g<shortSHA>` (the `g` prefix keeps SemVer valid when shas are numeric/leading-zero), and optionally runs tests.
- Buildah builds and pushes the image to Quay using credentials from the VSO-managed `quay-auth` Secret (`gitops/data/registry/quay`). Repos should be public when possible to avoid pull secrets.
- Multi-arch is supported when the pipeline `platforms` param is set (defaults to amd64).

## Deploy automation
- Argo CD Image Updater watches the Quay repo with allow-tags `regexp:^v\\d+\\.\\d+\\.\\d+-commit\\.g[0-9a-f]{7,}$` and strategy `semver`.
- On new allowed tags, Image Updater writes back to this repo’s values file (per-app path), commits to `main`, and pushes.
- Argo CD auto-syncs the Application; the Deployment rolls out the new image.
- Composite `appVersion` in the umbrella chart captures the exact mix of service tags; `make verify-release` enforces alignment.

## Rollback
- Rollbacks happen in git: revert the values change (and appVersion if needed) and let Argo sync. See `docs/ROLLBACK.md`.

## Checklist for adding/maintaining a service
- App repo has semver tags and avoids committing manifests/secrets.
- Tekton trigger registered with the app repo webhook; secret seeded in Vault; EventListener Route reachable from GitHub.
- Quay repo exists; pipeline has push credentials; Image Updater has pull access (public or pull secret).
- Application annotations include Image Updater alias, allow-tags regex, write-back target, and semver strategy.
- Values file starts on a valid `vX.Y.Z-commit.g<sha>` tag; env overlays kept in sync.
- Argo CD repo creds allow write access so Image Updater commits succeed.
