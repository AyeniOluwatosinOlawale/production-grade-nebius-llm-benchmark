# Production-Grade LLM Inference Benchmark — Nebius H100

Benchmarks **Qwen/Qwen3-27B** across a 2×3 matrix of schedulers and inference engines on Nebius H100 SXM5 preemptible nodes.

| | vLLM `v0.33.0` | SGLang `v0.5.23-cu130` | TensorRT-LLM `26.10` |
|---|---|---|---|
| **llm-d** | [`llm-d-vllm/`](llm-d-vllm/) | [`llm-d-sglang/`](llm-d-sglang/) | [`llm-d-tensorrt/`](llm-d-tensorrt/) |
| **NVIDIA Dynamo** `1.6.1` | [`dynamo-vllm/`](dynamo-vllm/) | [`dynamo-sglang/`](dynamo-sglang/) | [`dynamo-tensorrt/`](dynamo-tensorrt/) |

Each stack is **fully self-contained** — deploy and tear down independently.

---

## Hardware

- **Node**: Nebius H100 SXM5 preemptible (`8gpu-128vcpu-1600gb`)
- **Per replica**: 2× H100 SXM5 (tensor parallel)
- **Model**: Qwen/Qwen3-27B · BF16 · `max_seq_len=32768`
- **KEDA**: scales 2→8 replicas, 300s cooldown for preemptible node spin-up

## KPIs Measured (all 6 stacks)

| Metric | Source |
|---|---|
| TTFT (Time to First Token) | k6 SSE client + engine `/metrics` |
| TPOT (Time Per Output Token) | k6 SSE client |
| Tokens/s | Prometheus recording rule → Grafana |
| KV-cache utilisation | Engine `/metrics` → Grafana |
| GPU utilisation | DCGM Exporter → Grafana |
| Request throughput (req/s) | Prometheus recording rule → Grafana |
| p95 / p99 latency | Engine histogram + k6 thresholds |

---

## Quick Start — Run Any Stack

```bash
# Pick any one of the 6 stacks
cd llm-d-vllm        # or llm-d-sglang, llm-d-tensorrt, dynamo-vllm, dynamo-sglang, dynamo-tensorrt

# 1. Install cluster dependencies (once per cluster)
bash scripts/install-deps.sh

# 2. Deploy the stack
bash scripts/deploy.sh

# 3. Run the benchmark
bash scripts/run-load-test.sh

# 4. Tear down
bash scripts/teardown.sh
```

## Run All 6 Sequentially

```bash
bash run-all.sh
```

## Stack Structure (each subdirectory)

```
<stack>/
├── nebius/              # Nebius H100 NodeGroup config
├── monitoring/          # Prometheus, Grafana, DCGM, KEDA helm values + dashboards
├── litellm/             # LiteLLM proxy (unified API endpoint)
├── llmd/ or dynamo/     # Scheduler-specific manifests
├── <engine>/            # Engine PVC + service
├── keda/                # ScaledObject(s)
├── load-test/           # k6 scripts (smoke, 35-min ramp, replica verify)
└── scripts/             # install-deps, deploy, run-load-test, teardown
```

## Grafana Dashboards

All 6 stacks expose identical dashboards (metrics normalised to `llm:*` recording rules):

- **GPU Overview** — GPU util %, VRAM used, power draw, SM occupancy
- **Throughput** — TTFT p95/p99, tokens/s, KV-cache %, req throughput, replica count

## Image Versions

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
