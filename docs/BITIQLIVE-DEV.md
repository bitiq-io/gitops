# Bitiq Local Runbook (ENV=local on Ubuntu host)

Goal
- Run the GitOps stack with HTTPS on an Ubuntu home server using CRC, dynamic DNS, and cert-manager (HTTP-01). Keep it easy to expand to SNO/prod later.

Prerequisites
- Ubuntu host reachable from internet with a dynamic DNS FQDN (e.g., `home.example.net`).
- Router/NAT forwards: TCP 80 and 443 → Ubuntu host.
- Installed: crc, oc, helm, git, jq.
- Repo cloned and on a branch with strfry + couchbase scaffolding.

CRC setup (resources and start)
- Memory/CPU (minimum): `crc config set memory 16384 && crc config set cpus 6`
- Start: `crc start`
- Login: `eval $(crc oc-env)` then `oc login -u kubeadmin -p $(crc console --credentials | sed -n 's/.*kubeadmin password: //p') https://api.crc.testing:6443 --insecure-skip-tls-verify`

Dynamic DNS and router
- Create an A record for your FQDN pointing to your WAN IP. Use your DDNS client to keep it updated.
- Forward TCP 80 and 443 from your router to the Ubuntu host.

Expose CRC router with systemd-managed `crc tunnel`
- Create a systemd unit `/etc/systemd/system/crc-tunnel.service`:
  [Unit]
  Description=Expose OpenShift Local router on host 80/443
  After=network-online.target
  Wants=network-online.target
  StartLimitInterval=0

  [Service]
  Type=simple
  Restart=always
  RestartSec=5
  ExecStart=/usr/bin/env bash -lc 'eval "$(crc oc-env)" && exec crc tunnel'

  [Install]
  WantedBy=multi-user.target
- Enable and start:
  sudo systemctl daemon-reload
  sudo systemctl enable --now crc-tunnel
- Verify: `ss -ltnp | rg ':80|:443'` shows a `crc` process listening.

Secrets and Vault seeding (non-destructive)
- Provide secrets via env vars (optional but recommended):
  export GITHUB_WEBHOOK_SECRET=...     # Tekton triggers webhook
  export ARGOCD_TOKEN=...              # Argo CD Image Updater API token
  export QUAY_USERNAME=... QUAY_PASSWORD=... QUAY_EMAIL=...
- Seed Vault (won’t overwrite existing keys by default):
  make dev-vault
- Overwrite policy (optional):
  DEV_VAULT_OVERWRITE=never  make dev-vault   # strict safety
  DEV_VAULT_OVERWRITE=always make dev-vault   # only if intentionally resetting
- Behavior is implemented in `scripts/dev-vault.sh` and documented in `docs/MIGRATION_PLAN.md`.

Bootstrap and Argo CD umbrella
- Fast path end-to-end helper:
  FAST_PATH=true ENV=local BASE_DOMAIN=<your-fqdn> AUTO_DEV_VAULT=true \
  ./scripts/local-e2e-setup.sh
- Or render the ApplicationSet locally to inspect:
  helm template charts/argocd-apps --set envFilter=local | less
- The ApplicationSet passes `strfryEnabled=true` and `couchbaseEnabled=true` for local; umbrella child Applications `app-strfry` and `app-couchbase-cluster` will reconcile when Argo CD syncs.

Certificates (HTTP-01 on local)
- Ensure cert-manager operator is installed (bootstrap-operators) and a local HTTP-01 ClusterIssuer exists (managed by a future `charts/cert-manager-config` chart).
- With `crc tunnel` and NAT in place, cert-manager solves ACME HTTP-01 challenges using your public FQDN and issues valid certificates for Routes.
- Verify certificates:
  oc get certificates -A
  oc get routes -n <app-ns>
  curl -I https://relay.<your-fqdn>

Strfry
- Chart: `charts/strfry` (StatefulSet, Service, Route, PVC). Host formed as `relay.<baseDomain>`.
- Local values: `charts/strfry/values-local.yaml` (10Gi PVC on default hostpath class; small resources).
- Enablement: via ApplicationSet parameter `strfry.enabled=true` for local.

Couchbase (single-node on CRC)
- Chart: `charts/couchbase-cluster` (CouchbaseCluster + buckets). Admin Secret projected via VSO.
- Local values: single-node, quotas sized for CRC, analytics disabled. Uses cluster default storage class when `storageClassRWO/RWX` are empty.
- Prerequisite: Couchbase Autonomous Operator (CAO) Subscription via `charts/bootstrap-operators` (to be added alongside this chart in a follow-up).

Troubleshooting tips
- Argo sync issues: check `openshift-gitops` app controller logs; confirm child Applications created.
- Secrets missing: ensure `make dev-vault` ran and VSO CRDs/operators are healthy; see `make audit-secrets`.
- Certs pending: confirm `crc tunnel` is active, NAT 80/443 to host, and the Route host resolves publicly to your WAN IP.
- Couchbase not reconciling: verify CAO is installed and CSV is Succeeded (`oc get csv -A | rg couchbase`).

Cleanup
- Remove dev Vault helper: `make dev-vault-down`
- Stop CRC tunnel service: `sudo systemctl disable --now crc-tunnel`
- Stop CRC: `crc stop`

Appendix: Quick verification checklist
- oc get ns bitiq-local                        # namespace exists
- oc get app -n openshift-gitops | rg bitiq    # umbrella + children
- oc get route -n bitiq-local                  # strfry/couchbase admin (if enabled)
- oc get secret -n openshift-pipelines quay-auth
- oc get secret -n openshift-gitops argocd-image-updater-secret
