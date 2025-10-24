# Strfry Data Migration Runbook (Legacy systemd → CRC StatefulSet)

This plan captures the exact steps needed to move the existing 43 GiB LMDB from the legacy `strfry` systemd instance running on **silver** into the CRC-backed StatefulSet. Follow the tasks in order. Items that require `sudo` are explicitly called out so a human operator can assist when needed.

---

## Prerequisites

1. **Context recap**
   - Legacy relay: systemd unit `strfry.service` on host `silver`, data in `/var/lib/strfry/`, config in `/etc/strfry.conf` and `/etc/strfry-router.conf`.
   - New relay: Kubernetes StatefulSet `strfry` in namespace `bitiq-local`, PVC `strfry-data` (499 Gi mounted via hostpath), config shipped via Helm chart.
   - Helm chart already mounts separate `strfry.conf` and `strfry-router.conf` via `subPath`, so we can reuse the existing config content if desired.

2. **Where commands run**
   - Commands prefixed with `ssh silver` run on the host.
   - Pure `oc …` commands run from the local workstation with cluster access.
   - Steps tagged **(sudo)** need to be executed by a human with sudo privileges on `silver`.

3. **Downtime window**
   - Exporting/importing through strfry’s CLI requires the legacy process to be stopped (per upstream README). Plan for a maintenance window.

---

## Task List

### 1. Capture configuration (optional but recommended)

```bash
ssh silver 'sudo cp /etc/strfry.conf /var/lib/strfry/strfry.conf.backup'
ssh silver 'sudo cp /etc/strfry-router.conf /var/lib/strfry/strfry-router.conf.backup'
```

These backups let us align the Helm values or roll back if we need the exact legacy knobs.

### 2. Stop legacy relay **(sudo)**

```bash
ssh silver 'sudo systemctl stop strfry'
```

*Why*: Ensures LMDB is consistent before export. Alternative zero-downtime flow (start second instance, graceful shutdown via `SIGUSR1`) is possible but more complex—this plan assumes a clean stop.

### 3. Export LMDB using `--fried` **(sudo)**

```bash
ssh silver 'sudo -u strfry /usr/local/bin/strfry export --config /etc/strfry.conf --fried | gzip > /var/lib/strfry/strfry-fried.jsonl.gz'
```

*Why*: Upstream recommends export/import instead of copying raw `.mdb` files. `--fried` speeds up the subsequent import. Gzip keeps disk usage manageable.

### 4. Prepare Kubernetes side

1. Scale the StatefulSet down (idempotent):
   ```bash
   oc scale statefulset/strfry -n bitiq-local --replicas=0
   oc wait pod/strfry-0 -n bitiq-local --for=delete --timeout=120s
   ```
2. Launch helper pod that mounts the PVC and has strfry binaries:
   ```bash
   cat <<'EOF' | oc apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: strfry-import
     namespace: bitiq-local
   spec:
     restartPolicy: Never
     containers:
       - name: strfry
         image: quay.io/paulcapestany/strfry:0d0faa1
         command: ["sleep","infinity"]
         volumeMounts:
           - name: data
             mountPath: /opt/strfry/strfry-db
           - name: config
             mountPath: /opt/strfry/strfry.conf
             subPath: strfry.conf
             readOnly: true
           - name: config
             mountPath: /opt/strfry/strfry-router.conf
             subPath: strfry-router.conf
             readOnly: true
     volumes:
       - name: data
         persistentVolumeClaim:
           claimName: strfry-data
       - name: config
         configMap:
           name: strfry-config
   EOF
   ```
   Wait for it to be `1/1 Running`.

### 5. Stream import into PVC

```bash
ssh silver 'sudo gzip -dc /var/lib/strfry/strfry-fried.jsonl.gz' \
  | oc exec -i -n bitiq-local strfry-import -- /opt/strfry/strfry import --fried
```

*Notes*
- No `--config` flag: the binary looks for `./strfry.conf`, which is provided via the ConfigMap mount.
- Command exits `0` when all events have been imported; watch for non-zero status or “rejected” summaries in stdout/stderr.

### 6. Clean up helper pod

```bash
oc delete pod/strfry-import -n bitiq-local
```

### 7. Bring StatefulSet back online

```bash
oc scale statefulset/strfry -n bitiq-local --replicas=1
oc rollout status statefulset/strfry -n bitiq-local
```

Verify:
- `oc logs statefulset/strfry -n bitiq-local --tail=50` shows normal startup with existing events (no warnings about fresh DB creation).
- Route `relay.cyphai.com` returns expected data and clients can query historical events.

### 8. Optional: disable old service permanently **(sudo)**

After confirming CRC relay is healthy:

```bash
ssh silver 'sudo systemctl disable --now strfry'
```

Remove the exported archive if space is needed:

```bash
ssh silver 'sudo rm /var/lib/strfry/strfry-fried.jsonl.gz'
```

---

## Rollback Plan

1. If the CRC import fails: delete the helper pod, remove partial data (`oc rsh strfry-import rm /opt/strfry/strfry-db/*`), and repeat from Task 5 using the existing archive.
2. To revert to the legacy service: re-enable and start `strfry.service` (`sudo systemctl start strfry`).
3. Archived gzip + config backups allow re-running the import later.

---

## Tracking

- Last edited: 2025-10-23
- Owner: Codex agent
- Status: Pending human run (export requires sudo)
