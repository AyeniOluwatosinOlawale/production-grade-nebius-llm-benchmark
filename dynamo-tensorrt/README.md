# nebius-dynamo-tensorrt

Kubernetes benchmark stack: **NVIDIA Dynamo** scheduler + **TensorRT-LLM 26.10 (Triton)** inference engine on **Nebius H100 preemptible nodes**, serving **Qwen/Qwen3-27B** with disaggregated prefill/decode.

## Stack Overview

| Component | Image / Version |
|---|---|
| Inference engine | `nvcr.io/nvidia/tritonserver:26.10-trtllm-python-py3` |
| Dynamo router | `nvcr.io/nvidia/dynamo:latest` |
| LiteLLM proxy | `ghcr.io/berriai/litellm:main-latest` |
| NATS JetStream | `nats:2.10-alpine` |
| etcd | `bitnami/etcd:3.5` |
| DCGM Exporter | `nvcr.io/nvidia/k8s/dcgm-exporter:3.3.0-3.2.0-ubuntu22.04` |
| Prometheus stack | `kube-prometheus-stack` (Helm) |
| KEDA | `kedacore/keda` (Helm) |

## Prerequisites

- Nebius MK8S cluster with H100 GPU nodepools
- `kubectl` configured for the cluster
- `helm` v3.x
- `k6` for load tests
- A Hugging Face token with access to `Qwen/Qwen3-27B`

Create the HF token secret before deploying:

```bash
kubectl create namespace llm-inference
kubectl create secret generic hf-token \
  --from-literal=token=<YOUR_HF_TOKEN> \
  -n llm-inference
```

## Quick Start

```bash
# 1. Install cluster-level dependencies (Prometheus, DCGM, KEDA)
./scripts/install-deps.sh

# 2. Provision the Nebius H100 nodepool (if not already present)
kubectl apply -f nebius/nodepool-h100-preemptible.yaml

# 3. Deploy the full stack
./scripts/deploy.sh

# 4. Run load tests
./scripts/run-load-test.sh
```

## Architecture

```
Client
  └── LiteLLM LoadBalancer :4000
        └── Dynamo Router :8080  (dynamo serve --component=Frontend)
              ├── NATS JetStream :4222  (prefill queue)
              ├── etcd :2379            (KV state store)
              ├── Prefill Workers x1-4  (trtllm-serve --disaggregated-prefill)
              └── Decode Workers  x2-8  (trtllm-serve --disaggregated-decode)
                    └── Shared PVC: tensorrt-model-cache (100Gi SSD)
```

Disaggregated prefill/decode means prefill and decode pods scale independently via KEDA.

## KPIs Measured

| KPI | Threshold |
|---|---|
| TTFT p95 | < 3 000 ms |
| TTFT p99 | — (recorded) |
| E2E latency p95 | < 15 000 ms |
| Tokens / second | tracked via `llm:tokens_per_second` |
| KV cache utilisation | tracked via `llm:kv_cache_util` |
| GPU utilisation (DCGM) | tracked via `DCGM_FI_DEV_GPU_UTIL` |
| HTTP error rate | < 5 % |

## Benchmarking Matrix

This repo is one of six engine × scheduler combinations benchmarked on the same Nebius H100 cluster:

| Repo | Scheduler | Engine |
|---|---|---|
| `nebius-dynamo-tensorrt` **(this)** | NVIDIA Dynamo | TensorRT-LLM 26.10 |
| `nebius-dynamo-sglang` | NVIDIA Dynamo | SGLang |
| `nebius-vllm-standalone` | None (vLLM native) | vLLM |
| `nebius-sglang-standalone` | None | SGLang |
| `nebius-triton-vllm` | Triton IS | vLLM backend |
| `nebius-lws-vllm` | LWS | vLLM |

## Teardown

```bash
./scripts/teardown.sh
```
