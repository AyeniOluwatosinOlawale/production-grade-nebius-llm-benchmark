# Benchmark Results — Nebius H100 SXM5 Run 1

**Date:** 2026-11-05  
**Hardware:** 8× H100 SXM5 (preemptible), Nebius eu-north1  
**Model:** Qwen/Qwen3-32B, tp=2, BF16, max_model_len=32768  
**Gateway:** LiteLLM 3 replicas → engine  

---

## llm-d + vLLM (Run 2 — Clean Baseline)

**Config:** 2 GPUs, 1 vllm-qwen3 replica, 3 LiteLLM replicas  
**Load:** 100 VU peak (short/medium/long/context workloads, 35 min)

| Metric | Value |
|---|---|
| Total iterations | 72,617 |
| Throughput | 34.27 req/s |
| http_req_failed | 0.09% (71/72617) |
| TTFT short p95 | 2.76s ✓ |
| TTFT medium p95 | 10.77s |
| TTFT long p95 | 20.08s |
| TTFT context p95 | 40.26s |
| E2E p95 | 9.61s |
| KEDA fired | No (100 VU insufficient to build queue on H100) |

---

## llm-d + vLLM (Run 3 — 500 VU Stress, In Progress)

**Config:** Same as Run 2 + 500 VU peak  
**Purpose:** Force KEDA autoscaling trigger

| Metric | Value |
|---|---|
| Status | In progress at time of data capture |

---

## Dynamo + vLLM (Run 1 — INVALID)

**Config:** 4 GPUs (2 prefill + 2 decode), NATS, etcd, 3 LiteLLM replicas  
**Result:** 100% failure — Dynamo router returned 404 for all requests

| Metric | Value |
|---|---|
| Total iterations | 282,874 |
| http_req_failed | 100% |
| Valid inference | 0 |
| Root cause | Router `/v1/models` empty — workers registered TCP endpoints but router did not discover model |

> ⚠️ Dynamo run 1 data is NOT valid inference benchmark data. All requests failed.

---

## GPU Cost Reference

| Stack | GPUs per replica | Cost/hr per replica |
|---|---|---|
| llm-d | 2 | $2.18 |
| Dynamo | 4 (prefill + decode) | $4.36 |

Nebius H100 SXM5: $8.72/hr ÷ 8 GPUs = **$1.09/GPU/hr**

---

## Raw Logs

See `results/logs/` for full k6 output per run.

---

## Next Steps

1. Fix Dynamo router model discovery (workers register but router shows empty `/v1/models`)
2. Re-run Dynamo with 500 VU after verification: `curl -X POST .../v1/chat/completions` must return real tokens
3. Run cost-normalised comparison: tokens/$ for llm-d vs Dynamo
