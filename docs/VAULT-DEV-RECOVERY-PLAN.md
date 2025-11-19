# Vault Dev Recovery & Bootstrap Plan

This document captures the current state of the `vault-dev` environment (CRC `ENV=local`), the desired end state, and the concrete tasks required for getting back to a healthy Argo CD application (`vault-dev-local`) without losing existing secrets.

## Current State Summary

- `vault-dev-local` Argo Application: **Synced / Progressing** — the Vault pod (`vault-dev-0`) is running, but the bootstrap Job is CrashLooping with `Vault already initialized but bootstrap Secret lacks tokens`.
- `vault-config-local`: **Synced / Healthy** after recreating the stuck `KubernetesAuthEngineRole`.
- `vault-bootstrap` Secret is missing; downstream automation can’t unseal Vault or recover root credentials.
- CRC hostpath driver keeps reusing old raft data (`/var/lib/csi-hostpath-data/<pvc-id>`), so even after deleting the PVC/PV, the bootstrap job encounters a pre-initialized raft directory and exits immediately.

## Desired End State

1. Vault data wiped clean in a controlled manner (after taking backups).
2. `vault-dev-bootstrap` Job initializes Vault exactly once, stores the root/unseal info in the `vault-bootstrap` Secret, and completes.
3. `vault-dev-local` and `vault-config-local` Argo apps report **Synced / Healthy**.
4. Previous secrets (KV paths, policies, auth roles) restored and validated.

## High-Level Plan

1. **Back Up Everything**
   - Export all KV data under `gitops/` (or other mounts) to JSON files outside the PVC.
   - Copy the existing raft directory (`/vault/file`) off the pod as a “last resort” snapshot.
   - Capture current policies/auth roles (`vault policy read`, `vault auth list`, etc.).
2. **Coordinate Maintenance Window**
   - Notify stakeholders (image updater, Tekton pipelines, etc.) that Vault will be unavailable.
   - Optionally pause dependent Argo apps to avoid repeated reconcile noise.
3. **Perform Clean Wipe & Re-init**
   - Scale the StatefulSet to zero and delete the bootstrap Job.
   - Delete the PVC/PV and manually remove the hostpath directory on node `crc`.
   - Recreate the namespace/PVC via Argo, keeping the statefulset at zero until the hostpath path is confirmed empty.
   - Scale the StatefulSet back up and watch the bootstrap Job logs until it completes and `vault-bootstrap` Secret contains root/unseal keys.
4. **Restore Secrets and Policies**
   - Replay the JSON exports using `vault kv put`.
   - Reapply any policies/auth bindings not covered by the bootstrap script.
5. **Validate**
   - `oc -n openshift-gitops get application vault-dev-local vault-config-local`.
   - Use `vault status` and a test `vault login` to ensure unseal + authentication work.
   - Spot-check a consumer (e.g., Tekton pipeline secret projection).

## Detailed Tasks for Codex Agent

### 1. Backup Phase
- [ ] Use `oc -n vault-dev exec` to run `vault status` and ensure current pod is reachable.
- [ ] Run `vault kv export -mount=gitops > tmp/vault-gitops-backup.json` (repeat per mount if needed).
- [ ] `oc rsync vault-dev-0:/vault/file tmp/vault-raft-backup` for a raw raft snapshot.
- [ ] Export policies and auth roles to files under `tmp/vault-backup/`.
- [ ] Commit or otherwise store backups outside of the PVC (e.g., encrypted blob or secure location) per secrets policy.

### 2. Maintenance Preparation
- [ ] Notify/record downtime window.
- [ ] Optionally pause dependent Argo apps (`argocd app suspend <name>`).

### 3. Clean Wipe & Re-init
- [ ] `oc -n vault-dev scale statefulset vault-dev --replicas=0`.
- [ ] Delete bootstrap Job and PVC: `oc -n vault-dev delete job vault-dev-bootstrap`, `oc -n vault-dev delete pvc data-vault-dev-0`.
- [ ] Remove lingering PV (`oc delete pv <id>`) and manually wipe `/var/lib/csi-hostpath-data/<pvc-id>` using `oc debug node/crc`.
- [ ] Ensure `/var/lib/csi-hostpath-data/<pvc-id>` is empty before scaling up.
- [ ] Re-sync `vault-dev-local` Argo application so the namespace/PVC reappear.
- [ ] Scale StatefulSet to 1 and tail the bootstrap Job (`oc -n vault-dev logs job/vault-dev-bootstrap -f`).
- [ ] Confirm Job completes and `oc -n vault-dev get secret vault-bootstrap -o yaml` contains non-empty `root_token`/`unseal_key`.

### 4. Restore & Verify Secrets
- [ ] `vault login <root token>` using the new secret.
- [ ] Replay KV exports (`vault kv put gitops/<path> @tmp/vault-gitops-backup.json`).
- [ ] Reapply policies/auth bindings if not handled automatically.
- [ ] Delete backup artifacts from the repo if they contain sensitive data (per policy).

### 5. Validation & Cleanup
- [ ] `oc -n openshift-gitops get application vault-dev-local vault-config-local` → expect `Synced / Healthy`.
- [ ] Run `vault status` from a pod (`vault-cli`) to ensure unsealed, initialized state with `active_time` current.
- [ ] Trigger a dependent workflow (e.g., Tekton pipeline) to ensure secrets mount correctly.
- [ ] Document final state in PR summary / Ops notes.

### Optional Follow-ups
- If CRC continues to pre-populate raft data automatically, consider:
  - Switching dev storage from `raft` to `file` temporarily.
  - Adjusting hostpath provisioner settings or cleaning the CRC VM disk entirely.
  - Adding a guard job that asserts the absence of `/vault/file/vault.db` before the bootstrap Job starts.

## References
- `docs/LOCAL-CI-CD.md` and `docs/LOCAL-RUNBOOK-UBUNTU.md` for local bootstrap flows.
- `charts/vault-dev` for Helm manifest details.
- Argo apps: `charts/bitiq-umbrella/templates/app-vault-dev.yaml`.

> Keep this file updated as steps are completed so future Codex agents can resume with full context.
