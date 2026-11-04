# nebius-dynamo-sglang

**Stack:** LiteLLM -> NVIDIA Dynamo -> SGLang (disaggregated prefill + decode) | Qwen3-27B | tp=2 BF16 | Nebius H100 preemptible

Part of a 6-repo benchmark suite (2 schedulers x 3 engines).

## Architecture

```
Client -> LiteLLM :4000 -> Dynamo Router :8080
                               |
           +-------------------+
           v                   v
    SGLang Prefill        SGLang Decode
    Workers (tp=2)        Workers (tp=2)
    Port 30000            Port 30000
Infrastructure: NATS JetStream + etcd
```

## Quick Start

```bash
./scripts/install-deps.sh
./scripts/deploy.sh
./scripts/run-load-test.sh
```

## Metrics: TTFT * TPOT * Tokens/s * KV-cache util * GPU util * Req throughput * p95/p99 latency
