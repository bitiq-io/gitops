# Capacity + Accelerators (GPU, optional Inferentia)

This repo manages Day‑2 cluster capacity primitives (additional `MachineSet`s, autoscaling) and accelerator operators so Argo CD can reconcile drift.

## What’s Implemented

- Capacity surface (safe defaults):
  - `charts/bitiq-umbrella/templates/app-cluster-capacity.yaml` creates an Argo CD `Application` named `cluster-capacity-<env>`.
  - Auto‑prune is disabled to avoid accidental node pool deletion.
  - Optional `ignoreDifferences` for `MachineSet.spec.replicas` to avoid fighting autoscalers.
- Capacity chart:
  - `charts/cluster-capacity` renders `MachineSet` + optional `MachineAutoscaler`, optional `ClusterAutoscaler`, and optional NVIDIA GPU Operator install (`Subscription` + `ClusterPolicy`).

## Enable the Capacity Application

1. In `charts/argocd-apps/values.yaml`, set for your env:
   - `capacityEnabled: true`
   - `capacityIgnoreMachineSetReplicas: true` (only if using autoscaling via `MachineAutoscaler`)
2. Configure `charts/cluster-capacity/values-<env>.yaml` (example: `values-prod.yaml`) and set `enabled: true`.

## Gather Required Cluster Facts

### Get `infraID` (infrastructureName)

```bash
oc get infrastructures.config.openshift.io/cluster \
  -o jsonpath='{.status.infrastructureName}{"\n"}'
```

## Instance Type Recommendations (Inference)

Given current AWS Spot vCPU quotas:

- GPU (`All G and VT Spot Instance Requests` = `4`): start with `g5.xlarge` (1x NVIDIA A10G)
- Inferentia (`All Inf Spot Instance Requests` = `8`): start with `inf2.xlarge` (Inferentia2)

If you need larger models or higher throughput, request quota increases before scaling up instance sizes/count.

### Copy an existing AWS MachineSet providerSpec (recommended)

Copy an existing worker MachineSet and extract `.spec.template.spec.providerSpec.value` as the starting point:

```bash
oc -n openshift-machine-api get machineset <existing-workerset> -o yaml
```

This avoids hand‑authoring AWS fields (subnets, security groups, IAM instance profile, AMI, tags, etc.).

## Configure a GPU MachineSet

Edit `charts/cluster-capacity/values-<env>.yaml`:

- Set `infraID`.
- Add a `machineSets[]` entry.
- Recommended labels/taints (from `session-handoff.md`):
  - Node labels:
    - `node-role.kubernetes.io/worker: ""` (keeps the node in the worker MCP)
    - `node-role.kubernetes.io/gpu: ""`
  - Node taint:
    - `nvidia.com/gpu=true:NoSchedule` (so only explicit GPU workloads land here)

Example skeleton (providerSpec is required; paste from an existing worker MachineSet):

```yaml
enabled: true
infraID: "<REPLACE_WITH_INFRA_ID>"

machineSets:
  - enabled: true
    # Recommended starter GPU: g5.xlarge (fits 4 vCPU Spot quota for G/VT)
    nameSuffix: gpu-g5-xlarge-us-west-2a
    replicas: 0
    machineRole: gpu
    machineType: gpu
    nodeLabels:
      node-role.kubernetes.io/worker: ""
      node-role.kubernetes.io/gpu: ""
    taints:
      - key: nvidia.com/gpu
        value: "true"
        effect: NoSchedule
    # providerSpec: <paste .spec.template.spec.providerSpec.value here>
```

## Autoscaling Notes (MachineAutoscaler)

- Enable a per‑pool autoscaler by setting `machineSets[].autoscaler.enabled=true` with `minReplicas`/`maxReplicas`.
- Also set `capacityIgnoreMachineSetReplicas: true` for that env so Argo CD does not fight replica drift caused by autoscaling.

## NVIDIA GPU Operator

Enable in `charts/cluster-capacity/values-<env>.yaml`:

```yaml
nvidia:
  enabled: true
  subscription:
    # Package name is commonly gpu-operator-certified; override if your catalogs differ.
    name: gpu-operator-certified
    channel: stable
    source: certified-operators
    sourceNamespace: openshift-marketplace
```

The chart also creates a default `ClusterPolicy` (`nvidia.com/v1`, `cluster-policy`) with a toleration for the `nvidia.com/gpu` taint. Adjust as needed for your OpenShift version and GPU Operator requirements.

## Validation (“Hello GPU”)

1. Scale the GPU MachineSet to `replicas: 1` (or enable autoscaling).
2. Confirm the node shows allocatable GPUs (`nvidia.com/gpu`) once the operator is healthy.
3. Apply the example pod in `docs/examples/gpu-smoke-pod.yaml` and confirm it schedules and can run `nvidia-smi` (or your preferred CUDA sample).

## Inferentia (Gated / Not Implemented Yet)

Inferentia/Neuron on OpenShift/RHCOS must be confirmed feasible/supportable in this environment before writing manifests.
