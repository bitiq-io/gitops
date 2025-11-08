# Post-mortem: toy-service Image Updater loop (2025-11-07 ↔ 2025-11-08)

## Summary
Starting 2025-11-07 15:51 UTC the `toy-service-local` Argo CD Application began oscillating between `v0.3.38-commit.c709549` and `v0.2.33-commit.5cf34a2`. Two different Argo CD Image Updater instances – one running on x86_64 (CRC) and another running on an Apple Silicon-based environment – were configured to write back to the same Helm values file on `main`. Because the toy-service container image after `v0.3.0` only shipped the linux/amd64 architecture, the arm64 updater kept selecting the newest **arm64**-compatible tag (`v0.2.33`). The amd64 updater kept promoting the newest tag (`v0.3.38`). The dueling automation produced hundreds of alternating commits and caused repeated CRC rollouts that crashed with `exec format error` whenever the arm64 image landed on the x86 cluster.

## Impact
- ~540 automated commits from Argo CD Image Updater + Tekton `gitops-maintenance` flooded `main`, degrading repo signal-to-noise and forcing every `git fetch` to download the churn.
- Tekton appVersion automation spent several CPU hours recomputing the umbrella chart for every oscillation.
- `bitiq-local/toy-service` crashed repeatedly because the `v0.2.33` arm64 image cannot start on the x86_64 CRC node, leaving the sample backend unavailable for local testing.
- CRC Argo CD continuously synced the Deployment, preventing other work from reconciling quickly and adding noise to alerting.

## Timeline (UTC)
| Time | Event |
| --- | --- |
| 2025-11-07 15:51 | `argocd-image-updater` (arm64) downgrades `charts/toy-service/values-local.yaml` to `v0.2.33` to match the newest available arm64 tag. |
| 2025-11-07 16:02–16:24 | CRC image updater repeatedly upgrades back to `v0.3.38`; Tekton recompute pipeline follows each flip with `chore(release)` commits. |
| 2025-11-08 00:00–16:35 | Loop continues roughly every 2 minutes, producing >500 commits and keeping the CRC Deployment in CrashLoopBackOff. |
| 2025-11-08 16:40 | Investigation confirms dual image updaters and the single-arch build gap. |
| 2025-11-08 17:05 | Paused toy-service Image Updater (`imageUpdater.toyService.pause=true`) across all envs and documented manual tagging instructions. |
| 2025-11-08 17:15 | Argo resyncs with the paused annotation; CRC Deployment stabilizes on `v0.3.38`. |

## Root Cause
- The toy-service container images published after v0.3.0 are single-architecture (linux/amd64 only).
- An external arm64-based cluster rendered the same `toy-service-local` Application, set its Image Updater platforms to `linux/arm64`, and wrote back to `charts/toy-service/values-local.yaml` on `main`.
- Both clusters used the same GitHub PAT and write-back path, so each update overwrote the other.

## Contributing Factors
- No guardrails prevented multiple clusters from writing to the same values file or branch.
- No CI check validated that a new tag carried the architectures declared by `imageUpdater.*.platforms`.
- The repo lacked a multi-arch build pipeline for toy-service, forcing arm64 users to downgrade.
- Alerting/log review did not surface the CrashLoop/commit storm until a human noticed Git history.

## Mitigation & Remediation
- Paused toy-service Image Updater annotations (via `imageUpdater.toyService.pause=true` and `toyServiceImageUpdater.pause=true` in ApplicationSet values). Both clusters now render the Application without Image Updater annotations, so no further automated write-backs occur.
- Re-aligned `charts/toy-service/values-*.yaml` to `v0.3.38-commit.c709549` and forced an Argo hard refresh to redeploy the healthy image.
- Documented the pause and the manual tag update process in `docs/LOCAL-CI-CD.md` so engineers know to use `scripts/pin-images.sh` until multi-arch builds ship.
- After confirming no other contributors depended on the noisy history, rewrote `main` so the repository only contains the two human commits (`fix(signet-trailer)` and `fix(umbrella)`). The pre-rewrite history is still available on backup branches:
  - `main-loop-backup` — the short-term branch created during the cleanup.
  - `bot-loop-history` — the original `main` with every bot commit for future reference/audits.
  - `release-please--branches--main` was reset to the rewritten main as part of the cleanup so release tooling follows the new lineage.

## Follow-up Actions
1. **Ship multi-arch toy-service builds** – extend the Tekton `bitiq-build-and-push` pipeline (and/or the sample repo’s GitHub Actions) to produce linux/amd64 and linux/arm64 images plus a manifest list per tag. Target: 2025-11-15 owner: Platform.
2. **Re-enable Image Updater only after multi-arch verification** – once `skopeo inspect docker://...:<tag>` reports both architectures, flip `toyServiceImageUpdater.pause` back to false and monitor for 48h. Target: after (1).
3. **Add architecture validation to `scripts/verify-release.sh`** – fail CI if `skopeo inspect` for each declared platform returns empty, preventing incompatible tags from merging. Target: 2025-11-16.
4. **Introduce per-cluster write-back segregation** – add an `imageUpdater.writeBackSuffix`/`clusterId` knob so parallel clusters write to different paths or branches by default, minimizing blast radius if automation diverges. Target: 2025-11-20.
5. **Rotate the GitHub PAT used by Image Updater** – move credentials to a short-lived token in Vault so stale clusters cannot keep committing indefinitely. Target: 2025-11-22.
