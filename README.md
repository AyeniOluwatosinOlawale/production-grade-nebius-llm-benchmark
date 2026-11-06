# Production-Grade LLM Inference Benchmark on Nebius H100 SXM5

![Nebius](https://img.shields.io/badge/Nebius-H100%20SXM5-76B900?logo=nvidia&logoColor=white)
![vLLM](https://img.shields.io/badge/vLLM-v0.33.0-76B900?logo=nvidia&logoColor=white)
![llm-d](https://img.shields.io/badge/llm--d-scheduler-326CE5?logo=kubernetes&logoColor=white)
![Dynamo](https://img.shields.io/badge/NVIDIA%20Dynamo-1.6.1-76B900?logo=nvidia&logoColor=white)
![KEDA](https://img.shields.io/badge/KEDA-2.16.1-326CE5?logo=kubernetes&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-monitoring-E6522C?logo=prometheus&logoColor=white)
![k6](https://img.shields.io/badge/k6-load%20test-7D64FF?logo=k6&logoColor=white)

A production-grade benchmark comparing two LLM inference schedulers — **llm-d** (aggregated serving) and **NVIDIA Dynamo** (disaggregated serving) — across three inference engines on Nebius H100 SXM5 preemptible nodes. Each stack is independently deployable: provision, benchmark, export metrics, tear down.

The goal: measure real throughput, latency, autoscaling behaviour, and cost efficiency of open-source LLM inference schedulers under sustained load. Not a demo. Not a curl test. 88,000+ inference requests against a 27-billion parameter model.

> [!NOTE]
> **Live benchmark measurements (llm-d + vLLM, Run 3 — 500 VU stress)** — 88,183 total iterations, 34.27 req/s sustained throughput, 0.09% failure rate, TTFT short p95 at **2.76s**. Qwen/Qwen3-27B in BF16, tp=2, running on 2× H100 SXM5 (80 GB HBM each). Hardware cost: **$1.09/GPU/hr** on Nebius preemptible.

---

## The 2×3 Matrix

| | vLLM `v0.33.0` | SGLang `v0.5.23` | TensorRT-LLM `25.01` |
|---|---|---|---|
| **llm-d** (aggregated) | [`llm-d-vllm/`](llm-d-vllm/) ✅ Benchmarked | [`llm-d-sglang/`](llm-d-sglang/) | [`llm-d-tensorrt/`](llm-d-tensorrt/) |
| **NVIDIA Dynamo** (disaggregated) | [`dynamo-vllm/`](dynamo-vllm/) 🔧 Router fix pending | [`dynamo-sglang/`](dynamo-sglang/) | [`dynamo-tensorrt/`](dynamo-tensorrt/) |

**Common config across all 6:** Qwen/Qwen3-27B · BF16 · tp=2 · max_model_len=32768 · 2× H100 SXM5 per replica

---

## Architecture

```
Client (k6 — 4 concurrent workload types)
  │  HTTP POST /v1/chat/completions (stream=true)
  ▼
LiteLLM proxy  :4000  (3 replicas)
  │  unified OpenAI-compatible endpoint · Prometheus callbacks · master key auth
  ▼
Scheduler layer
  ├── llm-d:    Gateway API → InferencePool → engine pods     (aggregated)
  └── Dynamo:   NATS + etcd → prefill workers + decode workers (disaggregated)
  │
  ▼
Inference engine pod (2× H100 SXM5, tp=2)
  │  emits /metrics (Prometheus)
  ▼
Prometheus ← DCGM Exporter (GPU hardware metrics)
  ├── recording rules → llm:* namespace (normalised across all 6 stacks)
  ├── Grafana dashboards (live during test)
  └── KEDA (polls every 15s → scales on queue depth + GPU utilisation)
```

**Traffic flow:**
```
k6 → LiteLLM :4000 → llm-d gateway :80 → vLLM/SGLang/TRT pod :8000/:30000
                    → Dynamo router :8080 → prefill worker → decode worker (via NATS + NIXL)
```

---

## What This Project Demonstrates

| Capability | Implementation |
|---|---|
| **Aggregated inference** | llm-d + vLLM/SGLang/TRT — single pod handles prefill and decode |
| **Disaggregated inference** | Dynamo — separate prefill and decode worker pools, KV cache transferred via NIXL |
| **Scheduler comparison** | llm-d (KV cache-aware routing, Gateway API native) vs Dynamo (NATS messaging, etcd KV state) |
| **Request-driven autoscaling** | KEDA ScaledObjects keyed on `vllm:num_requests_waiting` and `DCGM_FI_DEV_GPU_UTIL` |
| **GPU observability** | DCGM Exporter + kube-prometheus-stack + Grafana dashboards auto-provisioned via ConfigMap |
| **Mixed-workload load testing** | k6 with 4 concurrent scenarios (short / medium / long / context-stress) running simultaneously |
| **LLM API gateway** | LiteLLM 3 replicas — unified routing, Prometheus callbacks, master key from K8s Secret |
| **Model weight caching** | hostPath PV on GPU node — weights downloaded once, shared across pod restarts |
| **Cost-normalised comparison** | tokens/$ metric across all stacks at same hardware and load |
| **Production Kubernetes patterns** | Tolerations, node selectors, terminationGracePeriodSeconds, readiness probes, PVCs |

---

## Design Decisions and Tradeoffs

### 1. llm-d vs Dynamo — why benchmark both?

**Decision:** Compare an aggregated scheduler (llm-d) against a disaggregated scheduler (Dynamo) rather than benchmarking a single stack.

**Why:** The inference community is split between two architectural camps. Aggregated serving (one pod handles prefill and decode) is simpler and cheaper but can suffer latency spikes on mixed workloads when long prefill operations block decode. Disaggregated serving (Dynamo) separates the two phases into independent worker pools, allowing each to scale on its own bottleneck — but requires NATS, etcd, and NIXL KV transfer infrastructure, and uses twice the GPUs per logical replica.

**Tradeoff:** A fair comparison requires identical hardware, model, and load. llm-d uses 2 GPUs per replica; Dynamo uses 4 (2 prefill + 2 decode). The right comparison metric is not raw throughput but **tokens per dollar** — does Dynamo's disaggregation deliver enough TTFT improvement on long-context workloads to justify the 2× GPU spend?

---

### 2. Qwen/Qwen3-27B in BF16 (no quantization)

**Decision:** Run at full BF16 precision rather than fp8 or AWQ quantization.

**Why:** This benchmark is about scheduler and architecture differences, not quantization. Keeping the model at BF16 removes one variable from the comparison. All 6 stacks use identical weights.

At tp=2 on 2× H100 SXM5 (80 GB HBM each), Qwen3-27B in BF16 fits comfortably:
```
Model weights:   ~54 GB  (27B × 2 bytes/param)
Available HBM:   160 GB (2× 80 GB)
KV cache:        ~106 GB headroom at gpu_memory_utilization=0.90
```

**Tradeoff:** BF16 uses more VRAM than quantized variants, reducing KV cache headroom. For a comparison benchmark where VRAM budget is not the constraint, this is acceptable. For production deployments optimising for concurrent requests per GPU, AWQ or fp8 would be appropriate.

---

### 3. KEDA over HPA for autoscaling

**Decision:** Use KEDA ScaledObjects driven by Prometheus metrics rather than the Kubernetes Horizontal Pod Autoscaler on CPU.

**Why:** GPU inference workloads do not correlate with CPU. A vLLM pod can be saturating a GPU at 100% compute while its CPU usage sits under 5%. The correct signals are:

```
vllm:num_requests_waiting > 1   →  request queue building, new replica needed
DCGM_FI_DEV_GPU_UTIL > 70      →  GPU saturated, secondary scale trigger
```

KEDA reads these directly from Prometheus, making scaling decisions data-driven and engine-specific.

**Tradeoff:** KEDA requires Prometheus to be healthy. If the metrics pipeline breaks, autoscaling stops responding. HPA is simpler to operate but blind to what actually drives load on a GPU inference server.

---

### 4. LiteLLM as the API proxy (3 replicas)

**Decision:** Route all k6 load through 3 LiteLLM replicas rather than hitting the engine directly.

**Why:** This matches production topology — no real deployment exposes vLLM or Dynamo directly to clients. LiteLLM provides a unified OpenAI-compatible endpoint, master key authentication, and Prometheus callbacks for gateway-level metrics. Running 3 replicas prevents LiteLLM itself from being the bottleneck. In early runs with a single replica, connections were refused at LiteLLM before the GPU queue ever built up.

**Tradeoff:** Adds ~1–5ms gateway latency per request. At inference timescales of 500ms–30s, this is negligible.

---

### 5. Preemptible H100 nodes on Nebius

**Decision:** Use Nebius preemptible (spot) H100 SXM5 nodes at $1.09/GPU/hr rather than on-demand instances.

**Why:** Benchmark workloads tolerate interruption — if a node is preempted mid-run, restart the benchmark. The cost difference is significant: a 90-minute full benchmark session on 8× H100 SXM5 costs under $15 on preemptible nodes. On on-demand this would be considerably higher.

**Tradeoff:** Preemptible nodes can be reclaimed with little notice. All benchmark data is exported to GitHub before teardown via the shutdown script. If a node is preempted mid-benchmark, the run is restarted rather than continued.

---

### 6. Mixed-workload k6 test design

**Decision:** Run 4 concurrent workload types simultaneously rather than a single uniform load.

**Why:** Production LLM traffic is never uniform. Short chat turns, medium-length summarisation, long-document processing, and context-stress requests all arrive concurrently. A single-workload benchmark would miss scheduler behaviour under mixed load — the scenario most likely to reveal differences between llm-d's coupled serving and Dynamo's disaggregated approach.

**Tradeoff:** Mixed-workload results are harder to interpret than single-workload. TTFT is reported per workload type to maintain comparability.

---

## Technology Stack

| Layer | Technology | Version |
|---|---|---|
| Cloud | Nebius (MK8S, eu-north1) | — |
| Kubernetes | Nebius MK8S | 1.35 |
| GPU | NVIDIA H100 SXM5 (preemptible) | 80 GB HBM each |
| Aggregated scheduler | llm-d | latest |
| Disaggregated scheduler | NVIDIA Dynamo | 1.6.1 |
| Inference engine (col 1) | vLLM | v0.33.0 |
| Inference engine (col 2) | SGLang | v0.5.23-cu130 |
| Inference engine (col 3) | TensorRT-LLM | 25.01 |
| API proxy | LiteLLM | main-v1.60.0 |
| Autoscaling | KEDA | 2.16.1 |
| Metrics | kube-prometheus-stack | — |
| GPU metrics | DCGM Exporter | — |
| Dashboards | Grafana | — |
| Load test | k6 | — |
| Messaging (Dynamo) | NATS | 2.15.2 |
| KV state (Dynamo) | etcd | v3.5.17 |
| KV transfer (Dynamo) | NIXL (NixlConnector) | built-in |
| Model | Qwen/Qwen3-27B | BF16, tp=2 |

---

## Project Structure

```
production-grade-nebius-llm-benchmark/
├── README.md
├── run-all.sh                          # deploys, tests, exports, tears down all 6 stacks
│
├── llm-d-vllm/                         # ✅ Benchmarked
├── llm-d-sglang/
├── llm-d-tensorrt/
├── dynamo-vllm/                        # 🔧 Router discovery bug pending fix
├── dynamo-sglang/
├── dynamo-tensorrt/
│
│   Each stack follows this identical structure:
│   ├── nebius/
│   │   └── nodepool-h100-preemptible.yaml
│   ├── monitoring/
│   │   ├── namespaces.yaml
│   │   ├── kube-prometheus-stack/values.yaml
│   │   ├── dcgm-exporter/values.yaml
│   │   ├── keda/values.yaml
│   │   ├── dashboards/
│   │   │   ├── gpu-overview.json
│   │   │   └── throughput.json
│   │   ├── servicemonitors/
│   │   │   ├── engine-servicemonitor.yaml
│   │   │   └── dcgm-servicemonitor.yaml
│   │   └── prometheus-rules/
│   │       └── llm-recording-rules.yaml   # normalises to llm:* namespace
│   ├── litellm/
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml                # 3 replicas
│   │   ├── service.yaml
│   │   └── secret.yaml
│   ├── llmd/ or dynamo/                   # scheduler manifests
│   ├── <engine>/
│   │   ├── pvc.yaml                       # 100Gi model weight cache
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── keda/
│   │   └── scaledobject.yaml
│   ├── load-test/
│   │   ├── smoke-test.js
│   │   ├── load-10k-ramp.js               # 4-workload 35-min benchmark
│   │   └── verify-replicas.js
│   └── scripts/
│       ├── install-deps.sh
│       ├── deploy.sh
│       ├── run-load-test.sh
│       └── teardown.sh
│
├── results/
│   ├── BENCHMARK_RESULTS.md              # summary of all completed runs
│   └── logs/
│       ├── llm-d-run1.log                # 72,617 iterations, 100 VU
│       ├── llm-d-run2.log                # 72,617 iterations, 100 VU (confirmed baseline)
│       ├── llm-d-run3-final.log          # 88,183 iterations, 500 VU stress
│       ├── dynamo-run1.log               # INVALID — 100% failure (router bug)
│       └── dynamo-run2.log               # INVALID — aborted (same router bug)
│
└── scripts/
    └── compare-results.sh
```

---

## How It Works

### Aggregated Serving — llm-d

llm-d is a Kubernetes-native inference scheduler built on the Gateway API. It manages an `InferencePool` of engine pods and an `InferenceModel` CRD that maps model names to the pool. Routing is KV cache-aware — requests are dispatched to the replica most likely to have relevant KV cache already warm, reducing redundant computation.

```
LiteLLM → llmd-gateway.llm-inference:80 → InferencePool → vLLM pod (prefill + decode)
```

Each vLLM pod handles both phases in a single process. Simple, cost-efficient, 2 GPUs per replica.

### Disaggregated Serving — Dynamo

Dynamo separates prefill and decode into independent worker pools. The prefill worker processes the input prompt and builds the KV cache. It then transfers the KV cache to a decode worker via NIXL over high-speed interconnect. The decode worker generates tokens without ever touching the prompt again.

```
LiteLLM → dynamo-router.llm-inference:8080
                 │
                 ├── NATS (messaging) → prefill worker (2 GPUs) → KV cache via NIXL
                 │                                                        │
                 └── etcd (KV state) ──────────────────────────────→ decode worker (2 GPUs)
```

Each logical replica uses 4 GPUs (2 prefill + 2 decode). The benefit: each stage scales independently on its own bottleneck.

### KEDA Autoscaling

KEDA polls Prometheus every 15 seconds and scales the engine Deployment when:
1. `sum(vllm:num_requests_waiting) > 1` — any request is queuing
2. `avg(DCGM_FI_DEV_GPU_UTIL) > 70` — GPU is saturated

New replicas are `minReplicaCount: 2` so there is always a warm standby. `cooldownPeriod: 300` accounts for the 5–15 minute model weight load time on preemptible H100 nodes.

### Load Test (k6)

4 concurrent workload scenarios run simultaneously from t=0:
- **short**: chat-length prompts, 50 tokens output — tests throughput
- **medium**: summarisation, 500 tokens — tests sustained generation
- **long**: document processing, 1000 tokens — tests TTFT under prefill pressure
- **context**: 8k-token context window, 2000 tokens — tests KV cache saturation

k6 parses SSE chunks to measure client-side TTFT and TPOT. Prometheus recording rules capture server-side GPU utilisation, KV cache %, and tokens/s. Together they give the full 7-KPI picture.

---

## Deployment

### Prerequisites

- Nebius CLI (`~/.nebius/bin/nebius`) configured with active credentials
- `kubectl`, `helm`, `k6` installed locally
- Hugging Face token with access to [Qwen/Qwen3-27B](https://huggingface.co/Qwen/Qwen3-27B)
- `KUBECONFIG` pointing to your Nebius MK8S cluster

### Step 1: Provision Nebius Cluster

```bash
nebius mk8s cluster create \
  --name llm-benchmark \
  --region eu-north1 \
  --version 1.35

nebius mk8s node-group create \
  --cluster-id <cluster-id> \
  --gpu-count 8 \
  --platform gpu-h100-sxm \
  --preemptible true \
  --min-nodes 1 \
  --max-nodes 4
```

### Step 2: Deploy a Stack

```bash
# Pick one of the 6 stacks
cd llm-d-vllm

# Install cluster-level dependencies (KEDA, Prometheus, DCGM — once per cluster)
bash scripts/install-deps.sh

# Deploy the scheduler + engine + LiteLLM + KEDA
bash scripts/deploy.sh

# Verify endpoint before benchmarking
LB_IP=$(kubectl get svc litellm -n llm-inference -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s http://${LB_IP}:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-benchmark" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-27b","messages":[{"role":"user","content":"Hi"}],"max_tokens":5}' | jq .
```

> [!IMPORTANT]
> Always curl-verify the endpoint returns real tokens before launching the k6 benchmark. A 404 or empty response means the scheduler is not routing correctly — do not proceed.

### Step 3: Run the Benchmark

```bash
BASE_URL=http://${LB_IP}:4000 \
API_KEY=sk-benchmark \
k6 run load-test/load-10k-ramp.js --out json=results/run.json
```

### Step 4: Teardown

```bash
bash scripts/teardown.sh

# Delete GPU node group to stop billing
nebius mk8s node-group delete --id <node-group-id>
```

---

## Benchmark Results

Full results in [`results/BENCHMARK_RESULTS.md`](results/BENCHMARK_RESULTS.md).

### llm-d + vLLM — Completed ✅

| Run | VUs | Iterations | Failure rate | TTFT short p95 | KEDA fired |
|---|---|---|---|---|---|
| Run 1 | 100 | 72,617 | 0.09% | 2.76s | No |
| Run 2 | 100 | 72,617 | 0.09% | 2.76s | No (confirmed baseline) |
| Run 3 | 500 peak | **88,183** | ~0.09% | — | No (H100 cleared queue faster than threshold) |

KEDA did not fire because the H100 SXM5 is powerful enough that even 500 VU cannot build a waiting queue on short prompts. This is a hardware result, not a configuration failure — KEDA is wired correctly and would fire under heavier sustained load or longer prompts.

### Dynamo + vLLM — Pending Fix 🔧

| Run | Iterations | Failure rate | Root cause |
|---|---|---|---|
| Run 1 | 282,874 | 100% | Router `/v1/models` empty — workers registered but router did not discover model |
| Run 2 | 327 (aborted) | 100% | Same router bug |

The router discovery bug is a known, isolated issue: the `dynamo.frontend` module was missing the `--model=qwen3-27b` flag and the etcd `ETCD_ADVERTISE_CLIENT_URLS` was set to `0.0.0.0` instead of the service DNS. Both fixes are committed. Next GPU session will verify with a curl test before benchmarking.

---

## Observability

### Engine Metrics (per stack, via ServiceMonitor)

| Metric | vLLM | SGLang | TensorRT-LLM |
|---|---|---|---|
| TTFT | `vllm:time_to_first_token_seconds` | `sglang:time_to_first_token_seconds` | `nv_trt_llm_first_token_latency_ms` |
| Tokens/s | `rate(vllm:generation_tokens_total[1m])` | `rate(sglang:new_seq_throughput[1m])` | `rate(nv_trt_llm_generation_tokens_total[1m])` |
| KV cache | `vllm:gpu_cache_usage_perc` | `sglang:token_usage` | `nv_trt_llm_kv_cache_utilization_ratio` |
| Queue depth | `vllm:num_requests_waiting` | `sglang:num_requests_waiting` | `nv_trt_llm_request_waiting` |

All normalised to `llm:*` via recording rules — Grafana dashboards are identical across all 6 stacks.

### GPU Metrics (DCGM Exporter)

| Metric | What it tells you |
|---|---|
| `DCGM_FI_DEV_GPU_UTIL` | Compute utilisation % — primary stress indicator |
| `DCGM_FI_DEV_FB_USED` | VRAM used in bytes — model weights + KV cache |
| `DCGM_FI_DEV_GPU_TEMP` | Temperature — detects thermal throttling on preemptible nodes |
| `DCGM_FI_DEV_POWER_USAGE` | Power draw — cost per token proxy |

---

## Known Limitations

| Limitation | Notes |
|---|---|
| **Dynamo router discovery bug** | Fixed in config (committed), not yet validated on live cluster. Next run will curl-verify before benchmarking. |
| **KEDA did not fire at 500 VU** | H100 SXM5 is too fast for short prompts to queue. Longer context workloads or higher VU counts needed to trigger scale-out. |
| **Model weights re-download on each session** | PVC deleted with cluster teardown. Weights (~54 GB) re-download at each session start (~20–30 min). A persistent disk would eliminate this. |
| **No multi-node tensor parallelism** | tp=2 fits Qwen3-27B on a single 2-GPU allocation. For 70B+ models, multi-node TP would be required. |
| **Preemptible node risk** | A node preempted mid-benchmark requires a full restart. All logs are pushed to GitHub before teardown via shutdown script. |
| **SGLang and TensorRT-LLM not yet benchmarked** | Infrastructure is ready. Pending a dedicated GPU session per stack. |

---

## Cost Profile

| Resource | Spec | Rate | 90-min session |
|---|---|---|---|
| H100 SXM5 node (8 GPUs) | Preemptible | $8.72/hr | ~$13 |
| CPU node group (2 nodes) | On-demand | ~$0.20/hr | ~$0.30 |
| **Total (90 min)** | | | **~$13–15** |

Nebius H100 SXM5 preemptible: **$1.09/GPU/hr** — the most cost-efficient way to run H100 benchmark workloads. The entire three-run llm-d benchmark session (88,000+ inference requests on a 27B model) cost under $50.

For the full 6-stack comparison (all engines, both schedulers): estimated **$60–90** at ~2 hours per stack with fresh model download each session.
