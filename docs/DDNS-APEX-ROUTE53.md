Route 53 Apex DDNS for Home WAN IP

Goal
- Keep apex A records (e.g., cyphai.com, neuance.net, paulcapestany.com) synced to your changing ISP IP, while keeping www hosts as CNAME to your eero DDNS.

When to use
- Your WAN IP changes periodically and you cannot use apex CNAME/ANAME flattening to an external hostname. Route 53 doesn’t support CNAME at apex, so you must maintain a normal A record.

Overview
- www: CNAME → k7501450.eero.online (auto-updates via eero)
- apex: A → <current WAN IP>; update every few minutes using a small route53 updater on the server

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

Script: scripts/route53-apex-ddns.sh
- Keeps apex A in sync with current WAN IP; supports multiple zones.

Systemd service + timer
1) /etc/systemd/system/route53-apex-ddns.service
  [Unit]
  Description=Route 53 apex DDNS updater
  After=network-online.target
  Wants=network-online.target

  [Service]
  Type=oneshot
  Environment=AWS_PROFILE=route53-ddns
  ExecStart=/usr/local/bin/route53-apex-ddns.sh

2) /etc/systemd/system/route53-apex-ddns.timer
  [Unit]
  Description=Run Route 53 apex DDNS updater every 5 minutes

  [Timer]
  OnBootSec=30s
  OnUnitActiveSec=5m
  Unit=route53-apex-ddns.service

  [Install]
  WantedBy=timers.target

Enable and verify
- sudo install -m 0755 scripts/route53-apex-ddns.sh /usr/local/bin/route53-apex-ddns.sh
- sudo systemctl daemon-reload
- sudo systemctl enable --now route53-apex-ddns.timer
- journalctl -u route53-apex-ddns.service -n 50

Expected DNS shape per zone
- Apex A: 60s TTL → current WAN IP
- www CNAME: → k7501450.eero.online
- Optional: CAA 0 issue "letsencrypt.org"

Notes
- DNS-01 issuance is API-driven and does not require the apex A to be correct, but end-user HTTPS does. Keeping the apex updated avoids browser warnings when IPs change.

