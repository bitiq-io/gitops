# strfry (Nostr relay) chart

Purpose
- Deploy the strfry Nostr relay with persistent storage, Service, and Route on OpenShift. Designed for GitOps usage behind the `bitiq-umbrella` Application.

Key values
- `baseDomain` (string): Base domain for Route host; final host is `<hostPrefix>.<baseDomain>`.
- `hostPrefix` (string, default `relay`): Route host prefix.
- `image.repository`/`image.tag`: Container image and tag.
- `service.port` (int, default 7777): Relay TCP port.
- `persistence.enabled` (bool, default true): Enable PVC for state.
- `persistence.size` (string, default `10Gi`): PVC size.
- `persistence.storageClassName` (string, default empty): If empty, use cluster default (hostpath on CRC).
- `resources`: CPU/memory requests/limits sized for CRC by default.
- `config.strfryConf` / `config.routerConf`: Content for `strfry.conf` and router streams, projected via ConfigMap to `/opt/strfry`.
- `networkPolicy.*`: Default-deny NetworkPolicy toggle plus optional ingress/egress destinations (DNS always allowed; enable `networkPolicy.db` for Couchbase ports).

Local vs prod
- Local (CRC): leave `storageClassName` empty to bind to cluster default; keep resource requests small.
- Prod: set an ODF storage class (e.g., `ocs-storagecluster-ceph-rbd`) and tune resources accordingly.

Umbrella integration
- The umbrella chart exposes `strfry.enabled` (per env). When true, it deploys the child Application pointing at this chart with `baseDomain` set from the env.

Verification
- `oc get route -n <ns> strfry` and curl `https://<host>`.
