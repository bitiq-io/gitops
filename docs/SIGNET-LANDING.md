# Signet Landing Source

- Repository: https://github.com/signeting/signet-landing (public, Vite/React static site for signet.ing)
- Image: `ghcr.io/signeting/signet-landing:0.1.0` (multi-stage build, nginx-unprivileged on :8080). GHCR package needs to be public for pulls; the workflow `.github/workflows/publish.yml` builds/pushes and sets visibility.
- Origin: extracted from `signet-trailer/` in this repo on 2025-02-08.
- Deployment: new Helm chart at `charts/signet-landing/` (Route host `signet.ing`, cluster issuer override in `values-local.yaml`).
- Status: static-only; GitOps re-integration (chart/pipeline) tracked in `docs/SIGNET-SIGNUP-PLAN.md` (S1+).

Use the new repo for any landing-page UI changes. This repo should only contain deployment plumbing for the site going forward.
