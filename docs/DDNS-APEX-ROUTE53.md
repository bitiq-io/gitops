Route 53 Apex DDNS for Home WAN IP

Goal
- Keep apex A records (e.g., cyphai.com, neuance.net, paulcapestany.com) synced to your changing ISP IP, while keeping www hosts as CNAME to your eero DDNS.

When to use
- Your WAN IP changes periodically and you cannot use apex CNAME/ANAME flattening to an external hostname. Route 53 doesn’t support CNAME at apex, so you must maintain a normal A record.

Overview
- www: CNAME → k7501450.eero.online (auto-updates via eero)
- apex: A → <current WAN IP>; update every few minutes using a small Route 53 updater on the server
- TLS issuer pattern: single cert-manager ClusterIssuer with per‑zone Route 53 solvers (zone selectors). Ingresses are annotated with that one issuer (e.g., `letsencrypt-dns01-route53-local`).

Least-privilege IAM policy
- Create an IAM user (programmatic access) limited to the hosted zones you manage. Replace <ZONE_ID> with your IDs.

{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow","Action": ["route53:ListHostedZonesByName"],"Resource": "*"},
    {"Effect": "Allow","Action": ["route53:ListResourceRecordSets"],
     "Resource": [
       "arn:aws:route53:::hostedzone/Z02889471UKP31JE18HPE",
       "arn:aws:route53:::hostedzone/Z0726808X55WJNUN7BTX",
       "arn:aws:route53:::hostedzone/Z03183593TRC0TQ7HVQYU"
     ]},
    {"Effect": "Allow","Action": ["route53:ChangeResourceRecordSets"],
     "Resource": [
       "arn:aws:route53:::hostedzone/Z02889471UKP31JE18HPE",
       "arn:aws:route53:::hostedzone/Z0726808X55WJNUN7BTX",
       "arn:aws:route53:::hostedzone/Z03183593TRC0TQ7HVQYU"
     ]}
  ]
}

Install AWS CLI on the server
- Ubuntu: sudo apt-get update && sudo apt-get install -y awscli
- Configure credentials for a dedicated profile: aws configure --profile route53-ddns
  - Important: the systemd service runs as root. Configure the profile for root so the service can read it:
    - sudo -i
    - aws configure --profile route53-ddns
    - aws configure set region us-east-1 --profile route53-ddns
  - Alternative: use an EnvironmentFile with access keys (host-only, not in Git). Create `/etc/route53-apex-ddns.env` with:
    - AWS_ACCESS_KEY_ID=...
    - AWS_SECRET_ACCESS_KEY=...
    - AWS_DEFAULT_REGION=us-east-1
    Then uncomment `EnvironmentFile=-/etc/route53-apex-ddns.env` in the service example.

Script: scripts/route53-apex-ddns.sh
- Keeps apex A in sync with current WAN IPv4; supports multiple zones.
- WAN IP discovery uses a fallback chain (ipify → checkip → ifconfig.me).
- Optional dry-run: pass `--dry-run` (or `-n`) to preview changes without updating Route 53.
- Zones file (optional): pass `--zones-file /path/to/zones` (or set `ROUTE53_DDNS_ZONES_FILE`) to load domain→hostedZoneID mappings from a file instead of editing the script.
  - Accepted line formats (comments with `#` and blank lines ignored):
    - `cyphai.com=Z02889471UKP31JE18HPE`
    - `neuance.net Z0726808X55WJNUN7BTX`
    - `paulcapestany.com,Z03183593TRC0TQ7HVQYU`
  - Default search path if none provided: `/etc/route53-apex-ddns.zones`

Systemd service + timer
- Example unit files are provided for copy/paste:
  - docs/examples/systemd/route53-apex-ddns.service
  - docs/examples/systemd/route53-apex-ddns.timer

To install:
1) sudo install -m 0755 scripts/route53-apex-ddns.sh /usr/local/bin/route53-apex-ddns.sh
2) Optional zones file: sudo install -m 0644 docs/examples/route53-apex-ddns.zones /etc/route53-apex-ddns.zones
3) sudo install -m 0644 docs/examples/systemd/route53-apex-ddns.service /etc/systemd/system/route53-apex-ddns.service
   - If you installed the zones file, you can uncomment the Environment line in the service to set `ROUTE53_DDNS_ZONES_FILE=/etc/route53-apex-ddns.zones`.
4) sudo install -m 0644 docs/examples/systemd/route53-apex-ddns.timer /etc/systemd/system/route53-apex-ddns.timer
5) sudo systemctl daemon-reload
6) sudo systemctl enable --now route53-apex-ddns.timer

Manual verify
- One-shot run (dry-run): /usr/local/bin/route53-apex-ddns.sh --dry-run
- Logs: journalctl -u route53-apex-ddns.service -n 50

Example zones file
```
# /etc/route53-apex-ddns.zones
cyphai.com=Z02889471UKP31JE18HPE
neuance.net Z0726808X55WJNUN7BTX
paulcapestany.com,Z03183593TRC0TQ7HVQYU
```

Expected DNS shape per zone
- Apex A: 60s TTL → current WAN IP
- www CNAME: → k7501450.eero.online
- Optional: CAA 0 issue "letsencrypt.org"

Notes
- DNS‑01 issuance is API-driven and does not require the apex A to be correct, but end-user HTTPS does. Keeping the apex updated avoids browser warnings when IPs change.
- For TLS issuance across multiple domains/zones, prefer a single cert-manager ClusterIssuer with per‑zone Route 53 solvers (zone selectors). See charts/cert-manager-config/templates/clusterissuer-dns01-route53.yaml:1 and charts/cert-manager-config/values-local.yaml:1.

Testing and TTL notes
- TTL: Apex A records use TTL 60s. When the script uses public DNS as a fallback for reads (to avoid List permissions), a change made in Route 53 may take up to the TTL to be visible via resolvers. The periodic timer (every 5 minutes) is sufficient.
- Simulate a change without touching Route 53 (dry-run):
  - `/usr/local/bin/route53-apex-ddns.sh --wan-ip 203.0.113.10 --dry-run`
  - You should see “Plan: set <domain> A -> 203.0.113.10 (was: <current>)”. No writes occur.
- Force a change (use with care):
  - `/usr/local/bin/route53-apex-ddns.sh --wan-ip 203.0.113.10`
  - Verify with `dig +short @1.1.1.1 <domain> A`; then allow the next timer run (or run manually) without `--wan-ip` to restore to your real WAN IP.
