# nebius-llm-d-tensorrt

**Stack:** LiteLLM -> llm-d Gateway -> TensorRT-LLM | Qwen3-27B | tp=2 BF16 | Nebius H100 preemptible

Part of a 6-repo benchmark suite (2 schedulers x 3 engines).

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
| TensorRT-LLM | trtllm-serve, tp=2, 2xH100, BF16, port 8000 |
| KEDA | Autoscaler on `nv_trt_llm_request_queue_size > 5` |
| DCGM Exporter | GPU metrics |
| Prometheus + Grafana | Observability |

## Notes
- Uses `trtllm-serve` which serves directly from HuggingFace weights (no engine pre-build)
- Triton metrics on port 8002, HTTP inference on port 8000
- Metrics: TTFT - TPOT - Tokens/s - KV-cache util - GPU util - Req throughput - p95/p99 latency

## Load Test
5-phase, 35 min, ~10,000+ requests. Ramps 20 -> 150 -> 500 VUs.
Proves KEDA scales from minReplicas=2 to >=3 under load.

## Prerequisites
- Nebius MK8S cluster with H100 preemptible node pool
- kubectl configured
- Helm 3.x
- k6 (for load tests)
- HuggingFace token with Qwen3-27B access (set as `hf-token` secret)

## Directory Structure
```
nebius-llm-d-tensorrt/
├── nebius/                   # Nebius node pool config
├── monitoring/               # Prometheus, DCGM, KEDA Helm values + dashboards + rules
├── litellm/                  # LiteLLM proxy manifests
├── llmd/                     # llm-d install script + CRDs
├── tensorrt/                 # TensorRT-LLM PVC, Deployment, Service
├── keda/                     # KEDA ScaledObject
├── load-test/                # k6 smoke + ramp load test scripts
└── scripts/                  # install-deps, deploy, run-load-test, teardown
```
