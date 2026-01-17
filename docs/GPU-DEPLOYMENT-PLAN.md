# Signet GPU Inference on OpenShift AI 3.0 (RHOAI) — GitOps Deployment Plan (v2)

**Document date:** 2026-01-17

This document is a **standalone, GitOps-first implementation plan** that assumes:

* **CPU inference is never used** (hard constraint).
* With the current **2× L40S GPUs**, we run **exactly one model per GPU** (one chat model + one embeddings model).
* It documents **when/how multi-model-per-GPU can make sense** (and why it’s usually a bad idea on L40S right now).
* The sanity-check includes a **bursty, randomly fluctuating GPU stress test**.

Key claims are grounded in current docs (Jan 2026) with citations and short direct quotes. **Direct URLs are listed only inside code blocks.**

**Repo reality check (important):** this repo deploys workloads via **ApplicationSet → umbrella chart → child Argo CD Applications**. So “add a new chart” is not sufficient by itself — this plan includes the exact “wiring” steps an agent must do so Argo CD actually syncs the new components (see **5.0 Repo wiring (critical)**).

**Prod cluster access:** use the kubeconfig rules in `docs/CLUSTER-ACCESS.md` (do not copy or print kubeconfig contents).

---
**Primary objective (short-term):** Get GPUs **usable + testable ASAP** on prod OCP by deploying:

* **1× chat (LLM) service on GPU #1**
* **1× embeddings service on GPU #2**
  …then run a bursty stress test that yields clear GPU utilization evidence for GPU quota increases.

**Secondary objectives (medium-term):**

* Scale to **2 chat + 2 embeddings** once AWS “G and VT vCPU” quota reaches **16 vCPU** (enough for 4× `g6e.xlarge` if we stick to that size).
* Keep the existing **ENV=local** workflow intact (local GPU inference via Ollama or an equivalent), without forcing RHOAI to exist locally.

**Key assumption:** a working GPU node group + GPU Operator patterns are already managed via GitOps (taints/labels, DCGM dashboard, etc.).

---

## 0) Hard constraints and why the plan looks the way it does

### CPU inference is a hard “no”

So every “local” or “prod” inference endpoint must be backed by an accelerator (NVIDIA GPU today; Inferentia/Trainium maybe later). This plan never routes inference to CPU.

### Why “one model per GPU” (for now)

1. **Operational simplicity + predictable latency**: each model server owns the GPU, no contention guessing games.
2. **L40S cannot use MIG** (so we cannot slice into isolated GPU partitions):

> “Multi-Instance GPU (MIG) Support **No**”

3. Time-slicing exists, but it’s not isolation:

> “Unlike… MIG, there is **no memory or fault isolation** between replicas…”

4. vLLM typically runs **one “task” per server instance**:

> “Each vLLM instance only supports **one task**…”

So: **1 GPU ↔ 1 vLLM server ↔ 1 model task** is the clean baseline.

---

## 1) Compatibility and installation constraints

### OpenShift AI 3.0 prerequisites

* RHOAI 3.0 Operator install flow expects **OpenShift 4.19+**:

> “running OpenShift cluster, version **4.19 or greater**…”

* Current supported OCP versions listed for OpenShift AI 3.0 include 4.19 and 4.20.
* Install channel guidance in docs:

> “subscribe… in the **fast-3.x** channel”

### vLLM runtime version in RHOAI 3.0

Red Hat’s supported config lists **vLLM 0.11.0 (CUDA)** for OpenShift AI 3.0.
This matters for model support + API behavior.

---

## 2) Target state architecture

### Minimal RHOAI footprint (inference-focused)

We deploy OpenShift AI components **only as needed** to serve models quickly:

* **OpenShift AI Operator**
* **Dashboard** (useful for visibility + workflows)
* **KServe** (single-model serving platform)
* **cert-manager** (required for model serving platform (`kserve`))

### Per-model services (single namespace)

This plan deploys both model services into the **existing per-env application namespace** that this repo already manages via the umbrella (`charts/argocd-apps/values.yaml → envs[].appNamespace`, for example `bitiq-prod`). This avoids extra Argo CD RBAC work and keeps the GitOps wiring straightforward.

Each model gets:

* a KServe `InferenceService`
* a Route (OpenShift ingress)
* a token/auth strategy for programmatic access

### OpenAI-compatible APIs (why this is huge)

For the vLLM runtime in RHOAI:

> “The vLLM model-serving runtime is compatible with the OpenAI REST API…”

And vLLM itself highlights throughput + batching (this is the core reason we avoid Ollama’s “everything sequential” wall):

> “Continuous batching of incoming requests”

So Signet can standardize on OpenAI-ish contracts, even if the backend changes (NVIDIA now, maybe Neuron later).

---

## 3) Concrete model recommendations for *right now* (2 GPUs total)

For the initial phase, run **1 chat + 1 embeddings** model (one per GPU). The pair below is a pragmatic starting point given RHOAI’s vLLM runtime and the need for high parallel throughput.

### GPU allocation (now)

| GPU    | Service        | Task                   | Notes                              |
| ------ | -------------- | ---------------------- | ---------------------------------- |
| GPU #1 | Chat inference | `/v1/chat/completions` | interactive + latency sensitive    |
| GPU #2 | Embeddings     | `/v1/embeddings`       | throughput sensitive + concurrency |

### Chat model (GPU #1)

**Recommended starting point:** `Qwen/Qwen2.5-14B-Instruct`
Why:

* Strong general assistant performance for a 14B class model
* Commonly used with vLLM
* Good “quality per GPU” baseline

**Alternative (smaller/faster):** `Qwen/Qwen2.5-7B-Instruct`

*(We intentionally avoid over-promising “131k context” in prod: cap max context initially to avoid KV-cache memory explosions. More on that below.)*

### Embeddings model (GPU #2)

**Recommended “safe with vLLM embedding workflow” baseline:** `intfloat/e5-mistral-7b-instruct`
Why:

* vLLM docs/examples explicitly use it for embedding usage (good “known path” for first wiring).
* OpenAI-client-style embedding calls are supported because:

> “Our Embeddings API is compatible with OpenAI's Embeddings API…”

**Second embeddings model later (once 4 GPUs are available):** `BAAI/bge-m3` (great multilingual retrieval baseline) — but validate it against the deployed vLLM runtime before betting production on it.

---

## 4) vLLM endpoint behaviors (design constraints)

### Supported inference paths (RHOAI vLLM runtime)

The doc lists OpenAI-style endpoints including:

* `/v1/chat/completions`
* `/v1/completions`
* `/v1/embeddings`

### Important gotcha: embeddings endpoint requires an embedding model

> “The **embeddings endpoint**… can only be used with an **embedding model**… You cannot use generative models…”

So do not deploy the chat model and expect embeddings from it via `/v1/embeddings`. Run a dedicated embeddings deployment.

### Context length safety (avoid “works once, OOM later”)

RHOAI docs show adding runtime args like:

> “`--max-model-len=6144` sets the maximum context length…”

This is the primary “seatbelt.” For the initial deployment, we recommend:

* Start conservative (e.g., **8192** for chat)
* Increase only after observing steady behavior under burst load

---

## 5) GitOps implementation tasks (ArgoCD + Helm)

This section is written so an AI coding agent can execute it in this repo.

### 5.0 Repo wiring (critical)

This is the single most common “agent failure mode” in this repo: implementing a chart but **not** wiring it into the **ApplicationSet → umbrella** flow, so Argo never deploys it.

In this repo, to add any new deployable component, an agent must do **all** of the following:

1. **Create the new Helm chart** under `charts/<new-chart>/` with `values-common.yaml` and (if needed) `values-<env>.yaml`.
2. **Add a new child Argo CD Application template** in `charts/bitiq-umbrella/templates/app-<new-app>.yaml` pointing at `charts/<new-chart>`.
3. **Add a new enable flag (and any parameters)** in:
   * `charts/bitiq-umbrella/values-common.yaml` (documented defaults)
   * `charts/bitiq-umbrella/values.yaml` (safe fallbacks for linting)
4. **Thread the new values through the ApplicationSet generator**, by updating:
   * `charts/argocd-apps/templates/applicationset-umbrella.yaml` (add `elements[].<flag>` + matching `helm.parameters` entries)
   * `charts/argocd-apps/values.yaml` (set the flag for `envs[].name: prod`; keep `local` unchanged unless you explicitly want local to deploy it)
5. **RBAC / namespace safety:**
   * If the new app deploys to a namespace other than `appNamespace`, update `charts/bitiq-umbrella/templates/rbac-argocd-access.yaml` to grant Argo CD the required namespace RoleBinding(s).
   * If the new app deploys **cluster-scoped** resources (for example `DataScienceCluster`), add a dedicated `ClusterRole`+`ClusterRoleBinding` in `charts/bitiq-umbrella/templates/` (pattern: `rbac-argocd-*-cluster.yaml`).

If an agent follows the rest of this plan but misses step (2)–(4), **nothing will deploy**.

### 5.1 Add/verify required Operators via GitOps

We need:

1. **cert-manager Operator** (required by `kserve`)
2. **OpenShift AI Operator** (RHOAI)

**Implement via GitOps** (pattern consistent with this repo):

* Use `charts/bootstrap-operators/` for OLM Subscriptions (cert-manager is already included; add OpenShift AI following the same pattern).
* Use `charts/cert-manager-config/` only if additional cert-manager configuration (ClusterIssuers, DNS resolver overrides, etc.) is required.

GitOps deliverables:

* OLM `Subscription` resources (and any required `Namespace`/`OperatorGroup`) for cert-manager and OpenShift AI.
* Optional cert-manager configuration (`ClusterIssuer`, DNS resolver overrides, etc.) via `charts/cert-manager-config/`.

**Critical detail: don’t hardcode package/channel blindly.**
Instead, add a **README + a “discovery command”** to pin correctly per cluster:

```bash
# Discover exact package + channels in this cluster
oc get packagemanifests -n openshift-marketplace | grep -i -E 'rhods|openshift.*ai'

# Inspect channels + currentCSV
oc get packagemanifest <packageName> -n openshift-marketplace -o yaml | less
```

Then pin Subscription to the doc-recommended channel family:

> “fast-3.x channel”

**Repo-specific implementation notes (to keep local clean):**

* Add OpenShift AI as a **gated** subscription in `charts/bootstrap-operators/templates/` (for example, `subscription-openshift-ai.yaml`) with a values flag like `.Values.operators.openshiftAI.enabled`.
* Default `operators.openshiftAI.enabled=false` so `ENV=local` does not pull in RHOAI.
* In prod, enable it by threading a new env flag through `charts/argocd-apps/templates/applicationset-umbrella.yaml` and setting it in `charts/argocd-apps/values.yaml` for `envs[].name: prod`.

### 5.2 Deploy OpenShift AI via DataScienceCluster (DSC)

Docs show that installing AI components is done by creating/configuring a `DataScienceCluster` object.

Create a GitOps-managed DSC with **only what is needed**:

* Enable:

  * `dashboard`
  * `kserve`
* Disable/remove:

  * notebooks/workbenches/pipelines/etc (for now)

(Base the YAML on the structure shown in Red Hat docs; example below uses the doc’s “all Removed” skeleton and flips only `dashboard` + `kserve` to `Managed`.)

**Example DSC (minimal inference footprint):**

```yaml
apiVersion: datasciencecluster.opendatahub.io/v2
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    # Keep minimal: only enable what we need for KServe inference.
    dashboard:
      managementState: Managed
    kserve:
      managementState: Managed

    # Explicitly disable the rest so the intent is unambiguous.
    aipipelines:
      argoWorkflowsControllers:
        managementState: Removed
      managementState: Removed
    feastoperator:
      managementState: Removed
    kueue:
      defaultClusterQueueName: default
      defaultLocalQueueName: default
      managementState: Removed
    llamastackoperator:
      managementState: Removed
    modelregistry:
      managementState: Removed
      registriesNamespace: rhoai-model-registries
    ray:
      managementState: Removed
    trainingoperator:
      managementState: Removed
    trustyai:
      managementState: Removed
    workbenches:
      managementState: Removed
      workbenchNamespace: rhods-notebooks
```

**Repo-specific RBAC note:** `DataScienceCluster` is cluster-scoped. Ensure the Argo CD Application controller has RBAC to manage `datasciencecluster.opendatahub.io` resources (pattern: add a `ClusterRole`+`ClusterRoleBinding` in `charts/bitiq-umbrella/templates/`).

### 5.3 Ensure GPU scheduling constraints match existing patterns

Reuse existing GPU placement patterns (node labels/taints) already codified in this repo.

For each model-serving workload:

* `nodeSelector` (or node affinity) to GPU nodes
* `tolerations` for GPU taint
* resource request/limit:

  * `nvidia.com/gpu: 1`

### 5.4 Create two model deployments (KServe InferenceService)

Create two charts:

* `charts/signet-llm/`
* `charts/signet-embeddings/`

Each chart should template:

* Namespace (optional; repo-default is to deploy into the existing `appNamespace`)
* ServiceAccount (optional)
* Secret(s) for model access (HF token if needed; deliver via Vault/VSO—do not commit tokens)
* KServe `InferenceService` using the **vLLM runtime**
* Route (only if the platform doesn’t auto-provision a reachable endpoint; prefer the platform’s generated endpoint when available)
* NetworkPolicy (optional but recommended)

**Model source strategy (pick one):**

* **Fastest path:** pull from Hugging Face directly (requires egress + token for gated models).
* **More controlled:** store artifacts in S3-compatible object storage (more work day-0).

For “ASAP,” do HF pulls and move to S3 later.

**Agent-proofing requirements (so this doesn’t get stuck on guessing):**

1. **Discover the vLLM ServingRuntime name in-cluster**, then reference it from your `InferenceService`:

```bash
# The vLLM runtime may be namespaced (ServingRuntime) or cluster-scoped (ClusterServingRuntime),
# depending on how RHOAI installed it. Discover what's available first:
oc get crd | rg -i 'clusterservingruntimes|servingruntimes' || true

# Cluster-scoped runtimes (if present):
oc get clusterservingruntimes 2>/dev/null || true
oc get clusterservingruntimes -o name 2>/dev/null | grep -i vllm || true

# Namespaced runtimes (often shipped in redhat-ods-applications and/or copied into your app namespace):
oc get servingruntimes -A 2>/dev/null | grep -i vllm || true

# If you only want to inspect your app namespace, replace <APP_NS> (repo-default: bitiq-prod):
oc -n <APP_NS> get servingruntimes 2>/dev/null || true
```

2. **Start from the generic InferenceService shape used in Red Hat docs** (same CRD, different runtime/model):

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: signet-llm
spec:
  predictor:
    model:
      runtime: <vllm-servingruntime-name>
      # modelFormat and storageUri will vary by runtime/model source.
      modelFormat:
        name: <runtime-specific>
      storageUri: <runtime-specific>
      resources:
        requests:
          cpu: "2"
          memory: 16Gi
          nvidia.com/gpu: "1"
        limits:
          cpu: "4"
          memory: 32Gi
          nvidia.com/gpu: "1"
```

3. **Chat template compatibility:** the Red Hat inference-request doc notes:

> “As of vLLM v0.5.5, you must provide a chat template… If your model does not include a predefined chat template… use the `chat-template` command-line parameter…”

So:
* Prefer chat models with an embedded chat template (many instruct-tuned models ship one).
* If the deployed runtime requires it, create a custom vLLM ServingRuntime in Git and set the `chat-template` parameter explicitly.

---

## 6) Authentication and how the load test will call the endpoints

RHOAI docs describe:

* how to retrieve the **route**
* how to retrieve the **token**
* and that requests use **port 443** via OpenShift router

The stress test and microservices should standardize on:

* `LLM_BASE_URL` (chat route root, e.g. `https://…`)
* `EMBEDDINGS_BASE_URL` (embeddings route root)
* `OPENSHIFT_AI_TOKEN` (Bearer token)

Keep tokens out of Git; inject them at runtime via environment variables or VSO-managed Secrets.

**Important for GitOps correctness:** if Argo CD self-heal is enabled for the load-test Deployment (it is in this repo by default), manual `oc scale` changes will be reverted. Prefer running the load test by **committing a temporary value change** (replicas 0 → 1) and reverting it after the run.

---

## 7) Sanity checks (basic) — prove GPU wiring is correct in 5 minutes

### 7.1 Confirm pods landed on GPU nodes and got a GPU

```bash
# Repo-default: both services live in the env app namespace (e.g. bitiq-prod)
oc -n <APP_NS> get pod -o wide

# Confirm GPU resource allocated
oc -n <APP_NS> describe pod <pod> | grep -i -E 'nvidia.com/gpu|Limits|Requests'
```

### 7.2 Confirm the container can see the GPU

```bash
oc -n <APP_NS> rsh <pod>
nvidia-smi
```

### 7.3 Run one chat request + one embeddings request

Use curl against the Routes with `Authorization: Bearer …` (keep these as scripted checks in this repo).

---

## 8) The GPU stress test (bursty + random)

### What “success” looks like

During the test window (10–20 minutes):

* GPU util oscillates realistically (bursts, idle gaps, spikes)
* Both chat and embeddings endpoints show non-trivial throughput
* Prometheus/DCGM shows sustained GPU utilization over time
* Capture screenshots/exports of the graphs for GPU quota requests

### Implementation approach (GitOps-friendly)

Create `charts/signet-loadtest/` that installs:

* a `ConfigMap` containing a **k6** script
* a `Deployment` named `signet-loadtest` with `replicas: 0` by default

  * **To run (GitOps-safe):** commit a temporary values change to set replicas to `1`, let Argo sync, then revert to `0` after the window.
  * This avoids “Job reruns forever” problems and avoids Argo fighting manual scaling.

### k6 script behavior

* Randomly chooses **chat** vs **embeddings** per iteration
* Randomizes:

  * request sizes
  * token limits
  * sleep jitter
* Uses phases:

  * warm-up
  * burst
  * cool down
  * second burst

**Skeleton (agent should implement as ConfigMap data):**

```js
import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    bursty: {
      executor: 'ramping-vus',
      startVUs: 2,
      stages: [
        { duration: '2m', target: 10 },
        { duration: '3m', target: 35 },
        { duration: '2m', target: 5 },
        { duration: '3m', target: 45 },
        { duration: '2m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
};

const token = __ENV.OPENSHIFT_AI_TOKEN;
const chatBase = __ENV.LLM_BASE_URL;            // e.g. https://<route-host>
const embedBase = __ENV.EMBEDDINGS_BASE_URL;    // e.g. https://<route-host>

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomText(len) {
  // cheap variable-load generator
  const chunk = "signet nostr reputation receipts ";
  return chunk.repeat(Math.ceil(len / chunk.length)).slice(0, len);
}

export default function () {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`,
  };

  const doChat = Math.random() < 0.55;

  if (doChat) {
    const maxTokens = randInt(64, 512);
    const promptLen = randInt(200, 4000);
    const body = JSON.stringify({
      model: "deployed-chat-model-name",
      messages: [
        { role: "system", content: "You are a concise assistant." },
        { role: "user", content: randomText(promptLen) + "\nSummarize in bullets with actionable steps." }
      ],
      max_tokens: maxTokens,
      temperature: Math.random(),
      stream: false
    });

    http.post(`${chatBase}/v1/chat/completions`, body, { headers });
  } else {
    const batchSize = randInt(1, 16);
    const itemLen = randInt(50, 1500);
    const input = Array.from({ length: batchSize }, () => randomText(itemLen));

    const body = JSON.stringify({
      model: "deployed-embedding-model-name",
      input
    });

    http.post(`${embedBase}/v1/embeddings`, body, { headers });
  }

  // jitter to create non-steady-state load
  sleep(Math.random() * 1.5);
}
```

### Observability: proving GPU usage

If DCGM/GPU monitoring is already in place (as assumed), use it.
During the test:

* watch `nvidia-smi` on the node/pod
* capture Prometheus/DCGM graphs (GPU util, mem util, power)

Also, enable user workload monitoring if needed; the RHOAI inference doc notes:

> “cluster administrator has enabled user workload monitoring.”

**Deliverable for GPU quota request:** a screenshot (or exported CSV) showing GPU util over time + evidence of instance uptime.

---

## 9) Scaling plan once quota hits 16 vCPU

If we keep using `g6e.xlarge` (4 vCPU each):

* At 8 vCPU quota: max 2 instances → 2 GPUs → (1 chat, 1 embed)
* At 16 vCPU quota: max 4 instances → 4 GPUs → (2 chat, 2 embed)

**GitOps action:** bump GPU MachineSet replicas (managed via the existing cluster-capacity patterns).

Then deploy:

* Chat model #2 (comparison candidate)
* Embedding model #2 (comparison candidate)

---

## 10) When multi-model-per-GPU *might* make sense (and the tradeoffs)

### Time-slicing / MPS is possible, but…

OpenShift’s own guidance is explicit:

> “Unlike… MIG, there is **no memory or fault isolation**…”

And on L40S specifically:

> “MIG Support **No**”

So multi-model-per-GPU is only worth it when:

* workloads are **bursty** and GPUs are mostly idle
* tail latency spikes are acceptable
* the operational risk of one workload destabilizing another (OOM/fault coupling) is acceptable

---

## 11) Local development narrative (keep ENV=local without forcing RHOAI locally)

RHOAI is not something we casually “run on a laptop” like Ollama. So the sane approach is:

### Keep the existing ENV contract, change what it points to

* `ENV=prod`: point to in-cluster RHOAI routes (OpenAI-compatible)
* `ENV=local`: point to a **local GPU-backed** inference server:

  * Ollama on Apple Silicon (Metal) for chat/embeddings locally
  * or local `vllm serve` (on an NVIDIA home server) for closer parity
  * or a tiny “inference gateway” that makes both look the same to Signet services

This preserves the current GitOps/CRC workflow while still letting prod standardize on RHOAI.

---

# Direct reference links (critical docs)

```text
OpenShift AI 3.0 install (Self-Managed):
https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install

OpenShift AI 3.0 supported configurations (includes vLLM version, OCP versions):
https://access.redhat.com/articles/rhoai-supported-configurations

RHOAI: making inference requests to deployed models (OpenAI-style endpoints, Bearer token header, chat template notes):
https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/deploying_models/making_inference_requests_to_deployed_models

OpenShift 4.20 NVIDIA GPU architecture (time-slicing vs MIG isolation notes):
https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture

NVIDIA L40S specs (MIG support = No):
https://www.nvidia.com/en-us/data-center/l40s/

vLLM docs (continuous batching / performance features):
https://docs.vllm.ai/en/stable/

vLLM OpenAI-compatible server docs (Embeddings API compatibility):
https://docs.vllm.ai/en/stable/serving/openai_compatible_server/
```

---

## Recommended sequence (minimize thrash)

0. Do the **repo wiring** so Argo will actually deploy the new charts (**5.0 Repo wiring (critical)**).
1. Install **cert-manager** and **OpenShift AI Operator** via GitOps (discovery commands to pin channel/CSV correctly).
2. Apply a **minimal DSC** enabling `dashboard` + `kserve`.
3. Deploy **chat model** `InferenceService` (GPU #1) and verify `/v1/chat/completions`.
4. Deploy **embeddings model** `InferenceService` (GPU #2) and verify `/v1/embeddings`.
5. Turn on the **bursty k6 loadtest** and capture GPU metrics/screenshots for GPU quota escalation. 

This gets us to “GPUs in production doing real work” fastest, which is the prerequisite for everything else.

---
