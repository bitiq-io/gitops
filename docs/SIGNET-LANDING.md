# Signet Landing Source

- Repository: https://github.com/signeting/signet-landing (public, Vite/React static site for signet.ing)
- Image: `quay.io/paulcapestany/signet-landing:0.1.4` (multi-stage build, nginx-unprivileged on :8080, multi-arch). A GitHub Actions workflow in the app repo builds/pushes tags to Quay (repo is public; pull secret optional).
- Origin: extracted from `signet-trailer/` in this repo on 2025-02-08.
- Deployment: new Helm chart at `charts/signet-landing/` (Route host `signet.ing`, cluster issuer override in `values-local.yaml`).
- Status: static-only; GitOps re-integration (chart/pipeline) tracked in `docs/SIGNET-SIGNUP-PLAN.md` (S1+).

Use the new repo for any landing-page UI changes. This repo should only contain deployment plumbing for the site going forward.
