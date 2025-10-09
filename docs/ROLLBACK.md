# Rollback Runbook

Operational recipe for reverting deployments managed by this GitOps repo. Applies to all environments (`ENV=local|sno|prod`) managed by the `bitiq-umbrella-<env>` Argo CD Applications. Treat Git as the sole source of truth: never mutate workloads directly in the cluster unless an emergency forces it (fallback in [Section 6](#6-emergency-cli-fallback-avoid)).

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

## 2. Revert the offending change

1. Use Git to revert the commit that introduced the bad tag (preferred):

   ```bash
   git revert --no-edit <commit-sha>
   ```

   If you already have a clean revert commit available (for example, you cherry-picked the rollback), ensure that it covers both the service values and `Chart.yaml`.

2. When the revert changes image tags, recompute the umbrella composite `appVersion` so it aligns with the restored image tags:

   ```bash
   make compute-appversion ENV=<env>
   ```

3. Confirm both `charts/bitiq-sample-app/values-<env>.yaml` and `charts/bitiq-umbrella/Chart.yaml` match the desired tag and fingerprint before committing:

   ```bash
   git diff
   ```

   Expected diff snippet (example restoring `sample-api` to `1.2.3`):

   ```
   -  tag: sample-api-v1.2.4-commit.abcd123
   +  tag: sample-api-v1.2.3-commit.9f8e7d6
   -appVersion: sample-api-v1.2.4-commit.abcd123
   +appVersion: sample-api-v1.2.3-commit.9f8e7d6
   ```

4. Commit and push the rollback with context in the message:

   ```bash
   git commit -am "revert: restore <service> to vX.Y.Z-commit.<sha>"
   git push origin <branch>
   ```

## 3. Trigger Argo CD to sync

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

## 4. Verify the rollback

1. Confirm Argo reports the expected composite fingerprint (`sample-api-v1.2.3-commit.9f8e7d6` in this example):

   ```bash
   argocd app get bitiq-umbrella-<env> | rg '^App Version:'
   ```

   Expected output:

   ```
   App Version: sample-api-v1.2.3-commit.9f8e7d6
   ```

2. Inspect the rendered manifest (optional) to double-check the tag:

   ```bash
   argocd app manifest bitiq-umbrella-<env> | rg 'image:'
   ```

   Expected snippet (for the target Deployment):

   ```
         image: quay.io/bitiq/sample-api:sample-api-v1.2.3-commit.9f8e7d6
   ```

3. Hit the service endpoint or run smoke checks (if available). Provide the environment to the helper target:

   ```bash
   make smoke ENV=<env>
   ```

   The smoke checks should pass and report the restored tag (if the script prints it).

## 5. Post-rollback follow-up

- Create an issue/ADR if the rollback surfaced a systemic problem (pipeline, testing gap, etc.).
- Update monitors or status pages if customers were impacted.
- If the reverted commit introduced multiple services, ensure each service’s values were restored and reflected in the composite fingerprint.

## 6. Emergency CLI fallback (avoid)

Only use these steps when Argo CD access is unavailable and production impact requires immediate mitigation. Any manual change **must** be mirrored back into Git right away using the Git-first procedure above.

1. Restore the previous Deployment revision in the affected namespace:

   ```bash
   oc rollout undo deploy/<service> --to-revision=<known-good-revision>
   ```

2. Verify the pods reverted to the desired image tag:

   ```bash
   oc get pods -l app=<service> -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].image}{"\n"}{end}'
   ```

3. As soon as the outage is mitigated, return to [Section 2](#2-revert-the-offending-change) and perform the Git revert so Argo reconverges and cluster/manual drift is eliminated.

## Reference

- Deterministic tag and composite versioning conventions: [`docs/CONVENTIONS.md`](./CONVENTIONS.md)
- Image Updater automation and write-back behavior: [`charts/bitiq-umbrella/templates/app-bitiq-sample-app.yaml`](../charts/bitiq-umbrella/templates/app-bitiq-sample-app.yaml)
- Tekton pipeline tag computation: [`charts/ci-pipelines/templates/pipeline.yaml`](../charts/ci-pipelines/templates/pipeline.yaml)
