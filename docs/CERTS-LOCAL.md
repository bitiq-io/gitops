# Local HTTPS with cert-manager (HTTP-01 on OpenShift Local)

Purpose
- Issue real TLS certificates for Routes on ENV=local using cert-manager and Let’s Encrypt with dynamic DNS and `crc tunnel`.

Requirements
- Dynamic DNS hostname resolving to your WAN IP (updated by your DDNS client).
- Router NAT: TCP 80 and 443 forwarded to the Ubuntu host.
- `crc tunnel` running as a systemd service to expose the OpenShift router on host 80/443.
- Red Hat cert-manager operator installed (via `charts/bootstrap-operators`).

Quick steps
- Confirm `crc tunnel` is active (see docs/BITIQLIVE-DEV.md).
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
- For clusters with the Red Hat cert-manager operator’s Route support, annotating a Route triggers certificate issuance and automatic TLS injection.
- Example Route annotations (add to the Route metadata):

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-http01-local
    haproxy.router.openshift.io/redirect-to-https: "true"
```

- Ensure the Route `spec.host` is a DNS name under your DDNS FQDN (e.g., `relay.home.example.net`).
- cert-manager will perform the HTTP-01 challenge via a temporary Ingress served by the OpenShift router. With `crc tunnel` and NAT in place, ACME should succeed.

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
- Pending challenges: ensure DNS resolves publicly to your WAN IP, NAT 80/443 to host, `crc tunnel` active.
- ACME rate limits: use the staging issuer first; switch to prod after success.
- OpenShift Route integration missing: fall back to the Certificate CR path with an Ingress, or add chart logic to populate Route `spec.tls` using the issued Secret.

References
- docs/BITIQLIVE-DEV.md (crc tunnel systemd unit and local runbook)
- docs/MIGRATION_PLAN.md (local HTTPS requirements and acceptance)
