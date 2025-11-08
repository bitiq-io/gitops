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

Expose CRC router to host 80/443
- On Linux (Ubuntu), `crc tunnel` may not be available. Use an iptables-based
  systemd unit to forward host ports 80/443 to the CRC VM router instead.

- Create `/etc/systemd/system/crc-router-forward.service`:
  [Unit]
  Description=Forward host 80/443 to CRC router
  After=network-online.target
  Wants=network-online.target

  [Service]
  Type=oneshot
  User=root
  RemainAfterExit=yes
  # Wait up to 5 minutes for CRC to be up and reporting an IP
  TimeoutStartSec=300
  # The CRC VM usually lives under the regular user's HOME (~/.crc). Set your username here.
  Environment=CRC_USER=<your-username>
  # Enable IPv4 forwarding and add NAT rules pointing to the CRC VM IP
  ExecStart=/bin/sh -c 'set -eu; \
    for i in $(seq 1 150); do IP=$(sudo -u "$CRC_USER" -H crc ip 2>/dev/null || true); [ -n "${IP:-}" ] && break; sleep 2; done; \
    if [ -z "${IP:-}" ]; then echo "CRC IP unavailable; is CRC started?" >&2; exit 1; fi; \
    sysctl -w net.ipv4.ip_forward=1; \
    if [ "$IP" = "127.0.0.1" ] || [ "$IP" = "localhost" ]; then \
      iptables -t nat -C PREROUTING -p tcp --dport 80  -j REDIRECT --to-ports 80  2>/dev/null || iptables -t nat -A PREROUTING -p tcp --dport 80  -j REDIRECT --to-ports 80; \
      iptables -t nat -C PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 443 2>/dev/null || iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 443; \
    else \
      iptables -t nat -C PREROUTING -p tcp --dport 80  -j DNAT --to-destination "$IP":80  2>/dev/null || iptables -t nat -A PREROUTING -p tcp --dport 80  -j DNAT --to-destination "$IP":80; \
      iptables -t nat -C PREROUTING -p tcp --dport 443 -j DNAT --to-destination "$IP":443 2>/dev/null || iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination "$IP":443; \
      iptables -t nat -C POSTROUTING -p tcp -d "$IP" --dport 80  -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -p tcp -d "$IP" --dport 80  -j MASQUERADE; \
      iptables -t nat -C POSTROUTING -p tcp -d "$IP" --dport 443 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -p tcp -d "$IP" --dport 443 -j MASQUERADE; \
    fi'
  ExecStop=/bin/sh -c 'IP=$(sudo -u "$CRC_USER" -H crc ip 2>/dev/null || true); \
    if [ "$IP" = "127.0.0.1" ] || [ "$IP" = "localhost" ] || [ -z "${IP:-}" ]; then \
      iptables -t nat -D PREROUTING -p tcp --dport 80  -j REDIRECT --to-ports 80  || true; \
      iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 443 || true; \
    else \
      iptables -t nat -D PREROUTING -p tcp --dport 80  -j DNAT --to-destination "$IP":80 || true; \
      iptables -t nat -D PREROUTING -p tcp --dport 443 -j DNAT --to-destination "$IP":443 || true; \
      iptables -t nat -D POSTROUTING -p tcp -d "$IP" --dport 80 -j MASQUERADE || true; \
      iptables -t nat -D POSTROUTING -p tcp -d "$IP" --dport 443 -j MASQUERADE || true; \
    fi'

  [Install]
  WantedBy=multi-user.target

  Notes:
  - If `crc ip` returns a real VM IP (for example `192.168.130.11`), the unit DNATs to it and
    adds MASQUERADE. If it returns `127.0.0.1` (user networking), the unit uses REDIRECT to
    the local ports forwarded by CRC; no MASQUERADE is needed in that case.
  - Requires root and iptables (nftables backend is fine on Ubuntu).
  - If your distro uses `nft` directly, you can adapt these rules to nft syntax.

- Alternative (only if your CRC build supports it): `crc tunnel`
  Some macOS/Windows builds include `crc tunnel`. If `crc --help` lists `tunnel`,
  you can run it under systemd. Ensure `$HOME` is set to avoid panics under systemd:
  [Unit]
  Description=Expose OpenShift Local router on host 80/443 (crc tunnel)
  After=network-online.target
  Wants=network-online.target

  [Service]
  Type=simple
  User=root
  Environment=HOME=/root
  Restart=always
  RestartSec=5
  ExecStart=/usr/bin/crc tunnel

  [Install]
  WantedBy=multi-user.target
- Enable and start (iptables forwarder):
  sudo systemctl daemon-reload
  sudo systemctl enable --now crc-router-forward
- Verify (from another machine hitting your host IP):
  - nc -vz <host-LAN-ip> 80; nc -vz <host-LAN-ip> 443
  - If your router forwards WAN 80/443 to this host, test from outside your LAN:
    curl -I http://<your-fqdn>
  - Inspect rules:
    - If `crc ip` is a VM IP: `sudo iptables -t nat -S PREROUTING | rg -- "to-destination .*:(80|443)"`
    - If `crc ip` is 127.0.0.1: `sudo iptables -t nat -S PREROUTING | rg -- "REDIRECT --to-ports (80|443)"`

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
- With host 80/443 forwarded to the CRC router (iptables forwarder or `crc tunnel` where available), cert-manager solves ACME HTTP-01 challenges using your public FQDN and issues valid certificates for Routes.
- Verify certificates:
  oc get certificates -A
  oc get routes -n <app-ns>
  curl -I https://relay.<your-fqdn>

Note (multi-zone DNS‑01): If port 80 is unavailable or you prefer DNS‑01, use a single cert-manager ClusterIssuer with per‑zone Route 53 solvers (zone selectors) rather than multiple Issuers. Keep all Ingress annotations pointing to that one issuer (e.g., `letsencrypt-dns01-route53-local`). See charts/cert-manager-config/templates/clusterissuer-dns01-route53.yaml:1 and charts/cert-manager-config/values-local.yaml:1 for the pattern and zone IDs.

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
- Certs pending: confirm the forwarder service is active (or `crc tunnel` if available),
  router 80/443 reach the CRC VM, and the Route host resolves publicly to your WAN IP.
- Couchbase not reconciling: verify CAO is installed and CSV is Succeeded (`oc get csv -A | rg couchbase`).

Cleanup
- Remove dev Vault helper: `make dev-vault-down`
- Stop CRC forwarder service: `sudo systemctl disable --now crc-router-forward`
- Stop CRC: `crc stop`

Appendix: Quick verification checklist
- oc get ns bitiq-local                        # namespace exists
- oc get app -n openshift-gitops | rg bitiq    # umbrella + children
- oc get route -n bitiq-local                  # strfry/couchbase admin (if enabled)
- oc get secret -n openshift-pipelines quay-auth
- oc get secret -n openshift-gitops argocd-image-updater-secret
