# nebius-dynamo-vllm

**Stack:** LiteLLM → NVIDIA Dynamo → vLLM (disaggregated prefill + decode) | Qwen3-27B | tp=2 BF16 | Nebius H100 preemptible

Part of a 6-repo benchmark suite (2 schedulers × 3 engines).

## Architecture
```
Client → LiteLLM :4000 → Dynamo Router :8080
                               │
           ┌───────────────────┤
           ▼                   ▼
    vLLM Prefill          vLLM Decode
    Workers (tp=2)        Workers (tp=2)
           │                   ▲
           └─── KV Cache ──────┘
                (NIXL/NVLink)

Infrastructure: NATS JetStream + etcd
```

## Quick Start
```bash
./scripts/install-deps.sh
./scripts/deploy.sh
./scripts/run-load-test.sh
```

## Metrics: TTFT · TPOT · Tokens/s · KV-cache util · GPU util · Req throughput · p95/p99 latency

## Load Test
5-phase 35 min, 10k+ requests. Scales prefill (GPU util trigger) and decode (queue depth trigger) independently via KEDA.
