# Local HTTPS with cert-manager (HTTP-01 on OpenShift Local)

Purpose
- Issue real TLS certificates for Routes on ENV=local using cert-manager and Let’s Encrypt with dynamic DNS and a host-level port-forwarder to CRC (iptables or router NAT).

Requirements
- Dynamic DNS hostname resolving to your WAN IP (updated by your DDNS client).
- Router NAT: TCP 80 and 443 forwarded to the Ubuntu host (or an equivalent forwarder).
- Host forwarder that maps ports 80/443 to the CRC router (iptables-based service from docs/BITIQLIVE-DEV.md). `crc tunnel` only exists on macOS/Windows builds; on Linux use the iptables service.
- Red Hat cert-manager operator installed (via `charts/bootstrap-operators`).

Quick steps
- Confirm the iptables forwarder systemd unit is active (docs/BITIQLIVE-DEV.md).
- Create a ClusterIssuer for Let’s Encrypt (start with staging to avoid rate limits).
- Annotate service Routes (if using Route integration), or create Certificate resources and consume the secret in an Ingress (advanced/alternative).

ClusterIssuer (HTTP-01, staging and prod)
- Save one of these as `cert-issuer-local.yaml` and apply with `oc apply -f cert-issuer-local.yaml`.

Staging (recommended for first run):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http01-local
spec:
  acme:
    email: you@example.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-http01-local-key
    solvers:
      - http01:
          ingress:
            class: openshift-default
```

Production:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http01-local-prod
spec:
  acme:
    email: you@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-http01-local-prod-key
    solvers:
      - http01:
          ingress:
            class: openshift-default
```

Route integration (preferred on OpenShift)
- For clusters with the Red Hat cert-manager operator’s Route support, annotating a Route triggers certificate issuance and automatic TLS injection. Ensure your host forwarder (iptables service) is up so ACME HTTP-01 traffic reaches the router.
- Example Route annotations (add to the Route metadata):

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-http01-local
    haproxy.router.openshift.io/redirect-to-https: "true"
```

- Ensure the Route `spec.host` is a DNS name under your DDNS FQDN (e.g., `relay.home.example.net`).
- cert-manager will perform the HTTP-01 challenge via a temporary Ingress served by the OpenShift router. With the iptables forwarder/NAT in place, ACME should succeed.

DNS-01 alternative (when TCP/80 is blocked)
- Some ISPs (or router configs) block inbound TCP/80, which prevents ACME HTTP-01. In that case, prefer DNS-01 with your DNS provider.
- Example ClusterIssuer for Route 53 (credentials in a Secret; manage via VSO in production):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns01-route53-local
spec:
  acme:
    email: you@example.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-dns01-route53-local-key
    solvers:
      - dns01:
          route53:
            region: us-east-1
            accessKeyIDSecretRef:
              name: route53-credentials
              key: access-key-id
            secretAccessKeySecretRef:
              name: route53-credentials
              key: secret-access-key
```

- Update Route annotations to use this ClusterIssuer:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-dns01-route53-local
```

- Ensure the referenced Secret exists in the same namespace as cert-manager’s controllers (typically `cert-manager`). Do not commit credentials; source them from Vault via VSO.
  - For Route 53, store AWS credentials in Vault at `gitops/cert-manager/route53` with keys `access-key-id` and `secret-access-key`. Example:
    - `vault kv put gitops/cert-manager/route53 access-key-id=AKIA... secret-access-key=...`
  - For HTTP API, use `gitops/data/cert-manager/route53`.
  - Minimum IAM policy for cert-manager Route 53 solver (IAM → Users → Add user (e.g., certmgr-dns01)):
    {
      "Version": "2012-10-17",
      "Statement": [
        {"Effect": "Allow", "Action": ["route53:ChangeResourceRecordSets"], "Resource": "arn:aws:route53:::hostedzone/*"},
        {"Effect": "Allow", "Action": ["route53:ListHostedZonesByName","route53:GetChange"], "Resource": "*"}
      ]
    }

Single issuer, per-zone solvers (recommended when you own multiple zones)
- Instead of creating multiple Issuers, use a single ClusterIssuer with per-zone solver entries that select by `dnsZones` and set `hostedZoneID` appropriately. This prevents hosted zone mismatches during TXT challenges and keeps Ingress annotations simple (one issuer name across all hosts).
- See charts/cert-manager-config/templates/clusterissuer-dns01-route53.yaml:1 for the templated form and charts/cert-manager-config/values-local.yaml:1 for zone IDs.

Certificate CR alternative (when Route annotation integration is not available)
- Create a Certificate referencing your hostname and desired target secret. Example:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: relay-cert
  namespace: bitiq-local
spec:
  secretName: relay-cert
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-http01-local
  dnsNames:
    - relay.home.example.net
```

- Consume the issued secret using an Ingress with TLS, or adapt your chart to project the certificate/key into the Route `spec.tls` fields. On OpenShift Routes, there is no `secretName` field; attaching TLS certs requires either the Route integration above or chart logic to copy PEMs from the Secret into `spec.tls` fields.

Verification
- Watch challenges/certificates:
  - `oc get challenges.acme.cert-manager.io -A`
  - `oc get orders.acme.cert-manager.io -A`
  - `oc get certificates -A`
- Confirm Route TLS:
  - `oc get route -n bitiq-local strfry -o yaml | rg 'tls:' -n` and curl the host: `curl -I https://relay.<your-fqdn>`

Troubleshooting
- Pending challenges: ensure DNS resolves publicly to your WAN IP, NAT 80/443 to host, and the iptables forwarder service is active (see docs/BITIQLIVE-DEV.md). On macOS/Windows builds you can use `crc tunnel` if it exists.
- If HTTP-01 is pending/failed and port 80 scans show filtered/closed from Internet vantage, switch to DNS-01.
- ACME rate limits: use the staging issuer first; switch to prod after success.
- OpenShift Route integration missing: fall back to the Certificate CR path with an Ingress, or add chart logic to populate Route `spec.tls` using the issued Secret.

References
 
Local dev seeding with make dev-vault
- You can provide Route 53 credentials via environment variables so the helper seeds Vault for you:
  - export AWS_ACCESS_KEY_ID=AKIA...
  - export AWS_SECRET_ACCESS_KEY=...
  - Optional route53-specific vars (take precedence):
    - export AWS_ROUTE53_ACCESS_KEY_ID=...
    - export AWS_ROUTE53_SECRET_ACCESS_KEY=...
- Then run: make dev-vault
- The helper writes to `gitops/cert-manager/route53` with keys `access-key-id` and `secret-access-key` if the env vars are present; otherwise it skips with a note. No secrets are committed to Git.
- docs/BITIQLIVE-DEV.md (iptables forwarder systemd unit, with optional macOS/Windows `crc tunnel` notes)
- docs/MIGRATION_PLAN.md (local HTTPS requirements and acceptance)
