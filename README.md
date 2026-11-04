# Production-Grade LLM Inference Benchmark — Nebius H100

Benchmarks **Qwen/Qwen3-27B** across a 2×3 matrix of schedulers and inference engines on Nebius H100 SXM5 preemptible nodes. Each stack runs independently — deploy, benchmark, export metrics, tear down, repeat.

| | vLLM `v0.33.0` | SGLang `v0.5.23-cu130` | TensorRT-LLM `26.10` |
|---|---|---|---|
| **llm-d** | [`llm-d-vllm/`](llm-d-vllm/) | [`llm-d-sglang/`](llm-d-sglang/) | [`llm-d-tensorrt/`](llm-d-tensorrt/) |
| **NVIDIA Dynamo** `1.6.1` | [`dynamo-vllm/`](dynamo-vllm/) | [`dynamo-sglang/`](dynamo-sglang/) | [`dynamo-tensorrt/`](dynamo-tensorrt/) |

---

## Hardware

| Resource | Spec | Used for |
|---|---|---|
| 2× H100 SXM5 (80 GB HBM each) | Model weights, KV cache, attention, matmuls | GPU |
| 8–32 vCPU | FastAPI server, tokeniser, scheduler loop, logging | CPU |
| 160–200 Gi RAM | Model metadata, request buffers, OS overhead | System RAM |
| 32 Gi `/dev/shm` | Tensor-parallel shared memory between the 2 GPUs (NCCL all-reduce) | RAM |

- **Node type**: Nebius H100 SXM5 preemptible (`8gpu-128vcpu-1600gb`)
- **Per replica**: 2× H100 SXM5 · tensor parallel (tp=2)
- **Model**: Qwen/Qwen3-27B · BF16 · `max_seq_len=32768` · `gpu_memory_utilization=0.90`
- **CPU nodes**: 2× `8vcpu-32gb` for monitoring, LiteLLM, KEDA, and CNI

---

## Architecture

```
Client (k6)
  │  HTTP POST /v1/chat/completions (stream=true)
  ▼
LiteLLM proxy  :4000       ← unified API, Prometheus callback, master key from K8s Secret
  │
  ▼
Scheduler
  ├── llm-d:   Gateway API → InferencePool → vLLM/SGLang/TRT pods
  └── Dynamo:  NATS + etcd → prefill workers + decode workers
  │
  ▼
Inference engine pod (2× H100, tp=2)
  │  emits /metrics
  ▼
Prometheus  ←  DCGM Exporter (GPU hardware metrics)
  │  recording rules → llm:* namespace
  ├── Grafana dashboards (live during test)
  ├── KEDA (autoscaler — polls every 15s)
  └── export-metrics.sh (dumps results before teardown)
```

---

## KPIs Measured (all 6 stacks)

| Metric | Source | Collection path |
|---|---|---|
| TTFT p95/p99 (per workload type) | k6 SSE client + engine `/metrics` | Prometheus histogram + k6 Trend |
| TPOT p95 (per workload type) | k6 SSE client | k6 Trend |
| **E2E latency p95 (per workload type)** | k6 (request sent → last token) + Prometheus | k6 Trend + recording rule |
| Tokens/s | Engine `/metrics` counter | `llm:tokens_per_second` recording rule |
| KV-cache utilisation % | Engine `/metrics` gauge | `llm:kv_cache_util` recording rule |
| GPU utilisation % | DCGM Exporter | `avg(DCGM_FI_DEV_GPU_UTIL)` |
| Request throughput (req/s) | Engine `/metrics` counter | `llm:request_throughput` recording rule |
| Replica count over time | kubectl readyReplicas | Logged every 60s during test |

Prometheus recording rules normalise all engine-specific metric names to the `llm:*` namespace so Grafana dashboards are identical across all 6 stacks.

---

## Load Test Design

Mixed-workload k6 test — **4 concurrent workload types** stressing both concurrency and context window length simultaneously:

| Workload | Input tokens | Output tokens | VUs | Starts |
|---|---|---|---|---|
| `short` | ~10 | 50 | 80–100 | t=0m |
| `medium` | ~500 | 500 | 40–60 | t=5m |
| `long` | ~2000 | 1000 | 20 | t=5m |
| `context` | ~8000 | 2000 | 10 | t=23m |

**5-phase schedule (35 min total):**

| Phase | Duration | Total VUs | Purpose |
|---|---|---|---|
| Warm-up | 5m | 20 | Confirm baseline stable |
| KEDA trigger | 8m | 140 | Saturate 2 replicas → `num_requests_waiting > 5` → KEDA fires |
| Hold | 10m | 140 | New pod loads 27B model weights (5–15 min on H100) |
| Context peak | 7m | 150 | 8k-token requests exhaust KV cache → GPU util > 70% → KEDA fires again |
| Ramp down | 5m | 0 | KEDA cooldown (300s) → replicas fall back to 2 |

**KEDA triggers:**
1. `sum(vllm:num_requests_waiting) > 5` — queue depth (fires at t≈5m15s)
2. `avg(DCGM_FI_DEV_GPU_UTIL) > 70` — GPU saturation (fires at t≈23m)

**Per-workload thresholds:**

| Metric | Short | Medium | Long | Context |
|---|---|---|---|---|
| TTFT p95 | < 3s | < 8s | < 20s | < 45s |
| E2E p95 | < 10s | < 60s | < 120s | < 240s |
| Error rate (all) | < 5% | | | |

---

## KEDA Autoscaling

```yaml
minReplicaCount: 2       # always 2 ready — no cold-start gating during test
maxReplicaCount: 8       # 16 GPUs max (8 replicas × 2 H100 each)
cooldownPeriod:  300     # 5 min — accounts for preemptible node spin-up time
pollingInterval: 15      # checks Prometheus every 15s
```

KEDA creates and manages an HPA automatically — do not create a separate HPA targeting the same Deployment.

---

## Monitoring Stack

| Component | Namespace | Purpose |
|---|---|---|
| kube-prometheus-stack | `monitoring` | Prometheus + Grafana + Alertmanager |
| DCGM Exporter | `monitoring` | GPU hardware metrics (DaemonSet on GPU node) |
| KEDA | `keda` | Prometheus-driven autoscaling |
| LiteLLM | `llm-inference` | Unified proxy + Prometheus callback |

**Grafana dashboards** (auto-provisioned via ConfigMap sidecar):
- `gpu-overview.json` — GPU util %, VRAM used GiB, power draw
- `throughput.json` — TTFT p50/p95/p99, E2E latency, tokens/s, KV-cache %, req/s, replica count

**Prometheus service address** (used by KEDA): `http://kube-prometheus-stack-prometheus.monitoring:9090`

---

## LiteLLM Configuration

- Prometheus success/failure callbacks enabled → LiteLLM request metrics in Grafana
- Master key injected from Kubernetes Secret (`litellm-secret`) — not stored in ConfigMap
- `max_tokens: 2048` default, `num_retries: 2`, `retry_after: 5s`
- Routes to scheduler: llm-d stacks → `http://llmd-gateway.llm-inference:80`, Dynamo stacks → `http://dynamo-router.llm-inference:8080`

---

## Quick Start — Run Any Stack

```bash
# Pick any one of the 6 stacks
cd llm-d-vllm   # or: llm-d-sglang | llm-d-tensorrt | dynamo-vllm | dynamo-sglang | dynamo-tensorrt

# 1. Install cluster dependencies (once per cluster)
bash scripts/install-deps.sh

# 2. Deploy the stack
bash scripts/deploy.sh

# 3. Run the 35-min benchmark
BASE_URL=http://<litellm-external-ip>:4000 bash scripts/run-load-test.sh

# 4. Export metrics before teardown
bash scripts/export-metrics.sh

# 5. Tear down (keeps monitoring namespace + Prometheus data)
bash scripts/teardown.sh
```

## Compare All 6 Stacks

Run all 6 sequentially then merge results:

```bash
bash run-all.sh                  # deploys, tests, exports, tears down each stack in order
bash scripts/compare-results.sh  # prints side-by-side comparison table from results/
```

Results are written to `results/<stack>-<timestamp>.json` (full Prometheus timeseries) and `results/<stack>-<timestamp>-summary.csv` (averages + peaks for all KPIs).

---

## Stack Structure

```
<stack>/
├── nebius/
│   └── nodepool-h100-preemptible.yaml   # H100 preemptible NodeGroup
├── monitoring/
│   ├── namespaces.yaml
│   ├── kube-prometheus-stack/values.yaml
│   ├── dcgm-exporter/values.yaml
│   ├── keda/values.yaml
│   ├── dashboards/
│   │   ├── gpu-overview.json
│   │   └── throughput.json
│   ├── servicemonitors/
│   │   ├── engine-servicemonitor.yaml
│   │   └── dcgm-servicemonitor.yaml
│   └── prometheus-rules/
│       └── llm-recording-rules.yaml     # normalises metrics to llm:* namespace
├── litellm/
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── secret.yaml                      # master key (K8s Secret)
├── llmd/ or dynamo/                     # scheduler manifests
├── <engine>/
│   ├── pvc.yaml                         # 100Gi model weights cache
│   ├── deployment.yaml
│   └── service.yaml
├── keda/
│   └── scaledobject.yaml                # (dynamo: scaledobject-prefill + decode)
├── load-test/
│   ├── smoke-test.js
│   ├── load-10k-ramp.js                 # 4-workload mixed stress test
│   └── verify-replicas.js
├── results/                             # exported metrics written here
└── scripts/
    ├── install-deps.sh
    ├── deploy.sh
    ├── run-load-test.sh
    ├── export-metrics.sh                # dumps all KPIs to JSON + CSV
    └── teardown.sh
```

---

## Image Versions (all pinned)

| Image | Tag |
|---|---|
| `vllm/vllm-openai` | `v0.33.0` |
| `lmsysorg/sglang` | `v0.5.23-cu130` |
| `nvcr.io/nvidia/tritonserver` | `26.10-trtllm-python-py3` |
| `nvcr.io/nvidia/ai-dynamo/vllm-runtime` | `1.6.1` |
| `nvcr.io/nvidia/ai-dynamo/sglang-runtime` | `1.6.1` |
| `nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime` | `1.6.1` |
| `ghcr.io/berriai/litellm` | `main-v1.60.0` |
| `quay.io/coreos/etcd` | `v3.5.17` |
| `nats` | `2.15.2-alpine` |

---

## Nebius Cluster Config

- **Cluster**: Nebius MK8S · eu-north1 · Kubernetes 1.35
- **GPU node group**: 1–4 nodes · `8gpu-128vcpu-1600gb` · preemptible · H100 SXM5
- **CPU node group**: 2–4 nodes · `8vcpu-32gb` · for monitoring + LiteLLM + KEDA + Cilium CNI
- **CNI**: Cilium (requires ≥2 nodes for operator quorum)
- **Storage**: `nebius-network-ssd` StorageClass for Prometheus (100Gi) and model PVC (100Gi)
