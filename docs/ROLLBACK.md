# Rollback Runbook

Operational recipe for reverting deployments managed by this GitOps repo. Applies to all environments (`ENV=local|sno|prod`) managed by the `bitiq-umbrella-<env>` Argo CD Applications. Treat Git as the sole source of truth: never mutate workloads directly in the cluster unless an emergency forces it (fallback in [Section 8](#8-emergency-cli-fallback-avoid)).

## Prerequisites

- Local clone with write access to the tracked Git branch.
- `git` and `argocd` CLI (or access to the Argo Web UI) configured for the target cluster.
- Awareness of the deterministic conventions in [`docs/CONVENTIONS.md`](./CONVENTIONS.md).

## 1. Identify the release to roll back

1. Inspect recent Git history for the service values and composite fingerprint. Replace `<env>` with `local|sno|prod` and `<service>` with the service you need to roll back:

   ```bash
   git log -p -- charts/bitiq-sample-app/values-<env>.yaml charts/bitiq-umbrella/Chart.yaml
   ```

2. Verify the currently deployed fingerprint in Argo (CLI or UI):

   ```bash
   argocd app get bitiq-umbrella-<env> --refresh --hard-refresh | rg '^App Version:'
   ```

   The `App Version` output matches the composite grammar `<svc>-vX.Y.Z-commit.<sha>_...`.

3. For multi-service incidents, capture both target tags and the composite `appVersion` (e.g., `toy-service-v0.2.33-commit.5cf34a2_toy-web-v0.1.8-commit.a064058`) so you can validate the rollback later.

## 2. Freeze the Image Updater

Pause Argo CD Image Updater before touching image tags so it does not immediately write a newer tag while you undo the change.

### 2.1 Git-first freeze (preferred)

1. On your rollback branch, edit `charts/bitiq-umbrella/templates/app-bitiq-sample-app.yaml:41` to set `argocd-image-updater.argoproj.io/dry-run: "true"`. To freeze **only** one service, adjust the `argocd-image-updater.argoproj.io/image-list` annotation at `charts/bitiq-umbrella/templates/app-bitiq-sample-app.yaml:13` and remove the entry for the service you want to hold.
2. Run the usual template sanity check so you catch typos early:

   ```bash
   make template
   ```

3. Commit the freeze so Argo can reconcile it:

   ```bash
   git commit -am "chore(image-updater): freeze sample app for rollback"
   ```

   Keep this commit separate from the rollback itself so you can revert it cleanly after validation.

4. Push the branch and, if you need the freeze immediately, trigger a sync of the umbrella Application:

   ```bash
   argocd app sync bitiq-umbrella-<env> --retry-limit 2
   ```

5. Confirm the Application now reports the dry-run flag:

   ```bash
   argocd app get bitiq-sample-app-<env> | rg 'argocd-image-updater.argoproj.io/dry-run'
   ```

   Expected output: `argocd-image-updater.argoproj.io/dry-run: true`.

### 2.2 Fallback: temporary annotation patch

If you cannot push a Git change quickly, apply a temporary annotation patch and record it so you can undo it after the rollback.

```bash
oc -n openshift-gitops patch application/bitiq-sample-app-<env> \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd-image-updater.argoproj.io/dry-run":"true"}}}'
```

For a per-service pause, patch the `image-list` instead (e.g., leave only `backend=<image>` to freeze the frontend). Always confirm the state:

```bash
argocd app get bitiq-sample-app-<env> | rg 'argocd-image-updater.argoproj.io'
```

Document any on-cluster patch in the incident log and plan to revert it in [Section 6](#6-unfreeze-the-image-updater).

## 3. Revert the offending change

1. Use Git to revert the commit that introduced the bad tag. Use `--no-commit` so you can include the composite appVersion recompute in the same commit for a deterministic rollback record:

   ```bash
   git revert --no-commit <commit-sha>
   ```

   If you already created a revert commit (e.g., with `--no-edit`), skip committing here and proceed to recompute `appVersion`; then commit only the `Chart.yaml` change separately with a clear message (e.g., `chore(umbrella): recompute appVersion`).

2. When multiple services moved together (backend + frontend), make sure both image tags are restored in `charts/bitiq-sample-app/values-<env>.yaml` before you continue.

3. Recompute the umbrella composite `appVersion` so it aligns with the restored image tags:

   ```bash
   make compute-appversion ENV=<env>
   ```

4. Confirm both `charts/bitiq-sample-app/values-<env>.yaml` and `charts/bitiq-umbrella/Chart.yaml` match the desired tags and fingerprint before committing:

   ```bash
   git diff
   ```

   Expected diff snippet (example restoring the backend to `toy-service-v0.2.9-commit.9f8e7d6` and the frontend to `toy-web-v0.1.8-commit.a064058`):

   ```
-    tag: toy-service-v0.3.1-commit.abcd123
+    tag: toy-service-v0.2.9-commit.9f8e7d6
...
-    tag: toy-web-v0.2.0-commit.4321cdef
+    tag: toy-web-v0.1.8-commit.a064058
-  appVersion: toy-service-v0.3.1-commit.abcd123_toy-web-v0.2.0-commit.4321cdef
+  appVersion: toy-service-v0.2.9-commit.9f8e7d6_toy-web-v0.1.8-commit.a064058
   ```

5. Commit and push the rollback with context in the message (single commit includes the revert and appVersion recompute):

   ```bash
   git commit -am "revert: restore backend+frontend to toy-service-v0.2.9/toy-web-v0.1.8"
   git push origin <branch>
   ```

## 4. Trigger Argo CD to sync

1. Allow auto-sync to converge or run a manual sync for faster recovery:

   ```bash
   argocd app sync bitiq-umbrella-<env> --retry-limit 2
   ```

   Expected output (truncated):

   ```
   Name:               bitiq-umbrella-<env>
   Operation:          Sync
   Phase:              Succeeded
   Sync Status:        Synced to <rollback-commit-sha>
   ```

2. Wait for the Application to report `Synced` and `Healthy`:

   ```bash
   argocd app wait bitiq-umbrella-<env> --health --sync --timeout 300
   ```

   Expected final line:

   ```
   Application bitiq-umbrella-<env> status is Synced; health is Healthy
   ```

   If the sync keeps failing, investigate the diff (`argocd app diff`) instead of forcing changes in the cluster.

   Alternatively, tail the controller logs if you need more context:

   ```bash
   oc logs -n openshift-gitops deploy/argocd-application-controller -f
   ```

## 5. Verify the rollback

1. Confirm Argo reports the expected composite fingerprint (should list both services for multi-service rollbacks):

   ```bash
   argocd app get bitiq-umbrella-<env> | rg '^App Version:'
   ```

   Expected output (example):

   ```
   App Version: toy-service-v0.2.9-commit.9f8e7d6_toy-web-v0.1.8-commit.a064058
   ```

2. Inspect the rendered manifests to double-check the tags for each Deployment:

   ```bash
   argocd app manifest bitiq-umbrella-<env> | rg -E 'image: .*toy-(service|web)'
   ```

   Expected snippet:

   ```
         image: quay.io/paulcapestany/toy-service:toy-service-v0.2.9-commit.9f8e7d6
         image: quay.io/paulcapestany/toy-web:toy-web-v0.1.8-commit.a064058
   ```

3. Hit the service endpoint or run smoke checks (if available). Provide the environment to the helper target:

   ```bash
   make smoke ENV=<env>
   ```

   The smoke checks should pass and report the restored tag (if the script prints it).

## 6. Unfreeze the Image Updater

Restore the Image Updater configuration once the rollback is stable so future tag bumps can flow normally.

### 6.1 Git-first unfreeze (preferred)

1. Revert the freeze commit or edit `charts/bitiq-umbrella/templates/app-bitiq-sample-app.yaml:41` back to `argocd-image-updater.argoproj.io/dry-run: "false"` and reintroduce any image entries you removed from the `image-list`.
2. Run `make template` to confirm the manifest matches expectations.
3. Commit and push the change:

   ```bash
   git commit -am "chore(image-updater): unfreeze sample app"
   git push origin <branch>
   ```

4. Sync the umbrella Application to apply the unfreeze and confirm the annotation flips back:

   ```bash
   argocd app sync bitiq-umbrella-<env>
   argocd app get bitiq-sample-app-<env> | rg 'argocd-image-updater.argoproj.io/dry-run'
   ```

   Expected output: `argocd-image-updater.argoproj.io/dry-run: false`.

### 6.2 Remove a temporary patch

If you used `oc patch` earlier, undo it now:

```bash
oc -n openshift-gitops patch application/bitiq-sample-app-<env> \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd-image-updater.argoproj.io/dry-run":"false"}}}'
```

Re-add any removed services in the `image-list` (replace the repositories if you customized them):

```bash
oc -n openshift-gitops patch application/bitiq-sample-app-<env> \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd-image-updater.argoproj.io/image-list":"backend=quay.io/paulcapestany/toy-service,frontend=quay.io/paulcapestany/toy-web"}}}'
```

Run `argocd app sync bitiq-umbrella-<env>` so Git reconverges with the desired state.

## 7. Post-rollback follow-up

- Create an issue/ADR if the rollback surfaced a systemic problem (pipeline, testing gap, etc.).
- Update monitors or status pages if customers were impacted.
- Confirm that every service involved in the rollback has the expected tag in Git (`values-<env>.yaml`) and in the running cluster before closing the incident.

## 8. Emergency CLI fallback (avoid)

Only use these steps when Argo CD access is unavailable and production impact requires immediate mitigation. Any manual change **must** be mirrored back into Git right away using the Git-first procedure above.

1. Restore the previous Deployment revision in the affected namespace:

   ```bash
   oc rollout undo deploy/<service> --to-revision=<known-good-revision>
   ```

2. Verify the pods reverted to the desired image tag:

   ```bash
   oc get pods -l app=<service> -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].image}{"\n"}{end}'
   ```

3. As soon as the outage is mitigated, return to [Section 3](#3-revert-the-offending-change) and perform the Git revert so Argo reconverges and cluster/manual drift is eliminated.

## Reference

- Deterministic tag and composite versioning conventions: [`docs/CONVENTIONS.md`](./CONVENTIONS.md)
- Image Updater automation and write-back behavior: [`charts/bitiq-umbrella/templates/app-bitiq-sample-app.yaml`](../charts/bitiq-umbrella/templates/app-bitiq-sample-app.yaml)
- Tekton pipeline tag computation: [`charts/ci-pipelines/templates/pipeline.yaml`](../charts/ci-pipelines/templates/pipeline.yaml)
