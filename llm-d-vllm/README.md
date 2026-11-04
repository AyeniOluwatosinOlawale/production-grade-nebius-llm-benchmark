# nebius-llm-d-vllm

**Stack:** LiteLLM → llm-d Gateway → vLLM | Qwen3-27B | tp=2 BF16 | Nebius H100 preemptible

Part of a 6-repo benchmark suite (2 schedulers × 3 engines). Only the engine/scheduler layer differs across repos.

## Quick Start
```bash
./scripts/install-deps.sh     # install KEDA, Prometheus, DCGM, llm-d operator
./scripts/deploy.sh           # apply all manifests
./scripts/run-load-test.sh    # 35-min load test with TTFT/TPOT measurement
```

## Stack Components
| Component | Role |
|---|---|
| LiteLLM | OpenAI-compatible proxy, LoadBalancer entry point :4000 |
| llm-d | K8s-native inference scheduler (InferencePool + InferenceModel CRDs) |
| vLLM | Inference engine, tp=2, 2×H100 per replica |
| KEDA | Autoscaler — scales on `vllm:num_requests_waiting > 5` |
| DCGM Exporter | GPU metrics: util, VRAM, power, temp |
| Prometheus + Grafana | Observability stack |

## Metrics Captured
- TTFT (Time to First Token) — p50/p95/p99
- TPOT (Time Per Output Token)
- Tokens/s throughput
- KV-cache utilisation %
- GPU utilisation % (DCGM)
- Request throughput (req/s)
- E2E latency p95/p99

## Load Test
5-phase, 35 min, ~10,000+ requests. Ramps 20 → 150 → 500 VUs.
Proves KEDA scales from minReplicas=2 to ≥3 under load.

## Prerequisites
- Nebius MK8S cluster with H100 preemptible node pool
- kubectl configured
- Helm 3.x
- k6 (for load tests)
- HuggingFace token with Qwen3-27B access (set as `hf-token` secret)
