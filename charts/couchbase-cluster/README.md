# couchbase-cluster chart

Purpose
- Deploy a CouchbaseCluster (via Couchbase Autonomous Operator) and environment-specific CouchbaseBucket resources.

Prerequisites
- Couchbase Autonomous Operator (CAO) Subscription installed via `charts/bootstrap-operators` (pinned channel per docs/OPERATOR-VERSIONS.md).
- Admin credentials provided via a Kubernetes Secret projected by VSO (Vault) with name matching `values.adminSecretName`.

Key values
- `adminSecretName` (string): Name of admin Secret (VSO-projected) with `username` and `password` keys.
- `servers.size` (int): Number of server pods (local default 1).
- `servers.services` (list): Services to run (data, index, query, search, eventing, analytics).
- `servers.storageClassRWO` (string): RWO class for default volumes. Leave empty on CRC to use default hostpath.
- `servers.storageClassRWX` (string): Optional RWX class for shared volumes (e.g., `ocs-storagecluster-cephfs` in prod).
- `quotas.*` (string): Memory quotas per service; set `analytics: 0Mi` to disable analytics in tight environments.
- `buckets[]` (list): Buckets to create with `name`, `memory`, optional `ioPriority`.
- `route.enabled`/`route.host`: Optional admin UI Route.

Local vs prod
- Local (CRC): `servers.size=1`, leave storage classes empty to bind to default hostpath, disable analytics (0Mi), small memory quotas and bucket sizes.
- Prod: multiple servers with anti-affinity, set `storageClassRWO`/`RWX` to ODF classes, tune quotas.

Umbrella integration
- The umbrella chart exposes `couchbase.enabled` (per env). When true, it deploys the child Application pointing at this chart.

Verification
- `oc get couchbasecluster`, `oc get couchbasebucket` in the app namespace.
- Admin Route (if enabled) should be reachable over HTTPS when cert-manager is configured.
