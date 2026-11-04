# nebius-llm-d-sglang

**Stack:** LiteLLM → llm-d Gateway → SGLang | Qwen3-27B | tp=2 BF16 | Nebius H100 preemptible

Part of a 6-repo benchmark suite (2 schedulers × 3 engines). Only the engine/scheduler layer differs across repos.

## Quick Start

```bash
./scripts/install-deps.sh
./scripts/deploy.sh
./scripts/run-load-test.sh
```

## Stack Components

| Component | Role |
|---|---|
| LiteLLM | OpenAI-compatible proxy :4000 |
| llm-d | K8s-native inference scheduler |
| SGLang | Inference engine, tp=2, 2×H100 per replica, port 30000 |
| KEDA | Autoscaler on `sglang:num_requests_waiting > 5` |
| DCGM Exporter | GPU metrics |
| Prometheus + Grafana | Observability |

## Metrics: TTFT · TPOT · Tokens/s · KV-cache util · GPU util · Req throughput · p95/p99 latency

## Directory Layout

```
nebius-llm-d-sglang/
├── nebius/                     # Nebius node pool manifests
├── monitoring/                 # Prometheus stack, DCGM, KEDA, dashboards, rules
├── litellm/                    # LiteLLM proxy config + deployment
├── llmd/                       # llm-d InferencePool + InferenceModel CRDs
├── sglang/                     # SGLang PVC, Deployment, Service
├── keda/                       # KEDA ScaledObject
├── load-test/                  # k6 smoke, ramp, replica-verify scripts
└── scripts/                    # install-deps, deploy, run-load-test, teardown
```

## Prerequisites

- Kubernetes cluster on Nebius with H100 GPU node pool
- `kubectl` configured for the target cluster
- Helm 3.x
- k6 (load testing)
- Node.js 18+ (verify-replicas.js)

## Deployment Details

### Namespaces

| Namespace | Purpose |
|---|---|
| `llm-inference` | SGLang, LiteLLM, llm-d CRDs |
| `monitoring` | Prometheus, Grafana, DCGM |
| `llm-d-system` | llm-d controller and EPP |
| `keda` | KEDA operator |

### SGLang Configuration

- Image: `lmsysorg/sglang:latest`
- Model: `Qwen/Qwen3-27B`
- Tensor parallelism: `tp=2` (2 GPUs per replica)
- Precision: `bfloat16`
- Port: `30000`
- Max prefill tokens: `32768`
- Chunked prefill size: `8192`
- Max running requests: `256`

### Autoscaling

KEDA triggers:
1. `sglang:num_requests_waiting > 5` → scale up
2. `DCGM_FI_DEV_GPU_UTIL > 70%` → scale up

Replica range: 2–8 (each replica = 2×H100)

### Preemption Handling

Pods tolerate `cloud.nebius.ai/preemptible` taint. `terminationGracePeriodSeconds: 120` gives SGLang time to drain in-flight requests before eviction.

## Observability

Access Grafana after deploy:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Dashboards:
- `LLM Throughput — nebius-llm-d-sglang` — TTFT, TPOT, tokens/s, latency percentiles
- `GPU Overview` — VRAM, utilisation, temperature per GPU

## Load Testing

```bash
# Quick smoke test (10 VUs, 30s)
./scripts/run-load-test.sh smoke

# Full ramp test (ramp to 10k concurrent over ~20min)
./scripts/run-load-test.sh ramp

# Check replica count during/after test
node load-test/verify-replicas.js
```

## Teardown

```bash
./scripts/teardown.sh
```

## Benchmark Suite

This repo is one of six:

| Repo | Scheduler | Engine |
|---|---|---|
| nebius-no-scheduler-vllm | none | vLLM |
| nebius-no-scheduler-sglang | none | SGLang |
| nebius-no-scheduler-tgi | none | TGI |
| nebius-llm-d-vllm | llm-d | vLLM |
| **nebius-llm-d-sglang** | **llm-d** | **SGLang** |
| nebius-llm-d-tgi | llm-d | TGI |
