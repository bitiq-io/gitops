# Ollama Helm Chart

This chart models the Ollama endpoint that downstream services use for embeddings. It supports two mutually exclusive operating modes:

- `external`: expose an external Ollama instance by projecting its endpoint details (ConfigMap/optional Secret) and, optionally, providing an `ExternalName` Service for stable in-cluster DNS.
- `gpu`: run Ollama inside the cluster on GPU-capable nodes. The chart creates a Deployment, Service, PersistentVolumeClaim, and optional ingress/Route with GPU-friendly scheduling knobs.

## Values

| Key | Description | Default |
| --- | ----------- | ------- |
| `mode` | Operating mode: `disabled`, `external`, or `gpu` | `disabled` |
| `baseDomain` | Optional base domain used when deriving external hosts | `""` |
| `external.host` | Explicit FQDN for the external Ollama endpoint. If left empty the chart stitches `external.hostPrefix` + `baseDomain`. | `""` |
| `external.hostPrefix` | Prefix used with `baseDomain` when `external.host` is empty | `ollama` |
| `external.scheme` | Scheme for derived URLs | `https` |
| `external.port` | Port for the external endpoint (used for derived URLs) | `11434` |
| `external.configMap.create` | Whether to create a ConfigMap with endpoint metadata | `true` |
| `external.configMap.name` | Name of the ConfigMap when created | `ollama-endpoint` |
| `external.configMap.hostKey` | Key used for the host entry | `OLLAMA_HOST` |
| `external.configMap.urlKey` | Key used for the URL entry | `OLLAMA_URL` |
| `external.configMap.extraData` | Additional key/value pairs to merge into the ConfigMap | `{}` |
| `external.service.enabled` | Create an `ExternalName` Service targeting the external host | `true` |
| `external.service.name` | Service name when created | `ollama-external` |
| `external.service.annotations` | Extra annotations for the external Service | `{}` |
| `gpu.replicaCount` | Replica count for the Ollama Deployment | `1` |
| `gpu.image.repository` | Container image repository | `ollama/ollama` |
| `gpu.image.tag` | Container image tag | `latest` |
| `gpu.image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `gpu.service.type` | Service type for in-cluster Ollama | `ClusterIP` |
| `gpu.service.port` | Service port for Ollama HTTP API | `11434` |
| `gpu.service.annotations` | Additional Service annotations | `{}` |
| `gpu.ingress.enabled` | Manage a Kubernetes Ingress for the Ollama Service | `false` |
| `gpu.route.enabled` | Manage an OpenShift Route for the Ollama Service | `false` |
| `gpu.persistence.enabled` | Attach persistent storage for model cache | `true` |
| `gpu.persistence.existingClaim` | Use an existing PVC instead of creating one | `""` |
| `gpu.persistence.size` | PVC size when created | `100Gi` |
| `gpu.persistence.storageClassName` | StorageClass override when creating a PVC | `""` |
| `gpu.persistence.accessModes` | PVC access modes | `["ReadWriteOnce"]` |
| `gpu.resources` | Container resource requests/limits (including `nvidia.com/gpu`) | see `values-common.yaml` |
| `gpu.nodeSelector` | Node selector for GPU nodes | `{}` |
| `gpu.tolerations` | Tolerations for GPU taints | `[]` |
| `gpu.affinity` | Affinity rules | `{}` |
| `gpu.runtimeClassName` | Optional runtime class (e.g., `nvidia`) | `""` |
| `gpu.securityContext` | Container security context | see `values-common.yaml` |
| `gpu.podSecurityContext` | Pod-level security context | see `values-common.yaml` |
| `gpu.env` | Additional environment variables for the Ollama container | `[]` |
| `gpu.envFrom` | Additional `envFrom` entries | `[]` |
| `gpu.extraVolumeMounts` | Extra volume mounts for the container | `[]` |
| `gpu.extraVolumes` | Extra pod volumes | `[]` |
| `gpu.startupProbe` / `livenessProbe` / `readinessProbe` | Probe overrides | see `values-common.yaml` |
| `networkPolicy.enabled` | Toggle NetworkPolicy rendering (applies to GPU mode) | `true` |
| `networkPolicy.ingress.allowOpenShiftIngress` | Allow router traffic by default | `true` |
| `networkPolicy.ingress.additional` | Additional ingress rules | `[]` |
| `networkPolicy.egress.allowDNS` | Allow DNS egress by default | `true` |
| `networkPolicy.egress.additional` | Additional egress rules | `[]` |

Secrets or credentials should be sourced through Vault operators (VCO/VSO); this chart only creates plaintext Kubernetes objects when explicitly instructed via the values above.
