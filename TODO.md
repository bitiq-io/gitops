# TODO - GitOps Repository

## Next Release Tasks

### ci/cd: End-to-end automation (ENV=local)
- ci(argo): add repo credential with write access for this repo in Argo CD (HTTPS PAT or SSH deploy key)
- ci(image-updater): create `argocd-image-updater-secret` with real ArgoCD API token (or document ESO path)
- ci(image-updater): set update strategy/semver (optional) and validate write-back to Helm values
- ci(tekton): set `charts/ci-pipelines/values.yaml` with real gitUrl and webhook secret; create `bitiq-ci` ns and grant image-pusher to pipeline SA
- ci(tekton): verify EventListener Route + GitHub webhook trigger a PipelineRun
- docs(runbook): add note on whoami-based sample, port 8080, health `/`

### docs: Documentation
- docs(readme): add quick links to SPEC.md and TODO.md
- docs(agents): refine safety rules for operator channel changes

### chore: Maintenance
- chore(ci): enable docs-check workflow (.github/workflows/docs-check.yml)

### security: Secrets strategy


### local-e2e: hardening
- ci(tekton): stop creating webhook Secret by default; gate via `triggers.createSecret` (done)
- dev(runbook): add clear steps to obtain Argo CD token via SSO; note the common `account '<user>' does not exist` error and fix (done)
- chore(make): add `image-updater-secret` helper target (done)

## Later
- docs: add ADRs for secrets management and repo credentials strategy
