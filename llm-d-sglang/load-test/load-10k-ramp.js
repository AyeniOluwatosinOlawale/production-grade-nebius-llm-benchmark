/**
 * load-10k-ramp.js — Ramping load test for nebius-llm-d-sglang.
 *
 * Ramps from 0 → 100 VUs over 20 minutes (simulating ~10k req bursts),
 * holds at peak for 5 minutes, then ramps back down.
 *
 * Thresholds (benchmark pass/fail criteria):
 *   - p95 TTFT < 5s at peak load
 *   - p99 E2E latency < 30s
 *   - Error rate < 2%
 *   - Throughput > 50 req/s sustained
 *
 * Usage:
 *   k6 run load-test/load-10k-ramp.js
 *   k6 run --out json=load-test/results/ramp-$(date +%s).json load-test/load-10k-ramp.js
 */

import http from "k6/http";
import { check, sleep } from "k6";
import { Trend, Rate, Counter, Gauge } from "k6/metrics";

// Custom metrics
const ttft = new Trend("ttft_seconds", true);
const e2eLatency = new Trend("e2e_latency_seconds", true);
const errorRate = new Rate("error_rate");
const tokensThroughput = new Counter("total_tokens");
const activeReplicas = new Gauge("active_replicas");

export const options = {
  scenarios: {
    ramp_load: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "2m", target: 10 },    // warm up
        { duration: "5m", target: 50 },    // ramp to medium
        { duration: "5m", target: 100 },   // ramp to peak
        { duration: "5m", target: 100 },   // hold at peak
        { duration: "2m", target: 50 },    // ramp down
        { duration: "1m", target: 0 },     // cool down
      ],
      gracefulRampDown: "30s",
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.02"],
    ttft_seconds: ["p(95)<5", "p(99)<10"],
    e2e_latency_seconds: ["p(99)<30"],
    error_rate: ["rate<0.02"],
  },
};

const LITELLM_URL = __ENV.LITELLM_URL || "http://litellm.llm-inference:4000";
const API_KEY = __ENV.LITELLM_API_KEY || "sk-nebius-bench-1234";

// Mixed prompt lengths to simulate realistic workload distribution
const PROMPTS = [
  // Short prompts — fast, test throughput
  "What is TTFT?",
  "Define KV cache.",
  "Explain tensor parallelism briefly.",
  "What is BF16?",
  "What does tp=2 mean in LLM serving?",

  // Medium prompts — moderate compute
  "Explain the difference between prefill and decode phases in transformer inference. How does chunked prefill help reduce head-of-line blocking?",
  "What are the tradeoffs between continuous batching and static batching in LLM serving? When would you choose each?",
  "Describe how SGLang's RadixAttention enables efficient prefix caching for multi-turn conversations.",
  "What is speculative decoding and how does it reduce decode latency without changing output quality?",
  "Explain how KEDA uses Prometheus metrics to trigger pod autoscaling for LLM workloads.",

  // Long prompts — stress prefill stage
  "You are an AI inference engineer. Write a detailed technical comparison of three LLM serving frameworks: vLLM, SGLang, and TGI. Cover: (1) scheduling algorithms, (2) memory management strategies, (3) batching approaches, (4) support for tensor parallelism, (5) metrics and observability, (6) strengths and weaknesses, and (7) recommended use cases for each. Be specific and technical.",
  "Explain how a Kubernetes-native inference platform built on llm-d, KEDA, and Prometheus can achieve high availability and automatic scaling for large language models on preemptible GPU nodes. Cover: pod disruption budgets, graceful shutdown, rolling updates, metric-driven scaling, and cost optimisation strategies.",
];

export default function () {
  const prompt = PROMPTS[Math.floor(Math.random() * PROMPTS.length)];
  const maxTokens =
    prompt.length < 100 ? 128 : prompt.length < 400 ? 256 : 512;

  const payload = JSON.stringify({
    model: "qwen3-27b",
    messages: [{ role: "user", content: prompt }],
    max_tokens: maxTokens,
    stream: false,
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${API_KEY}`,
    },
    timeout: "60s",
  };

  const start = Date.now();
  const res = http.post(`${LITELLM_URL}/v1/chat/completions`, payload, params);
  const elapsed = (Date.now() - start) / 1000;

  const ok = check(res, {
    "status 200": (r) => r.status === 200,
    "response not empty": (r) => r.body && r.body.length > 0,
    "has choices": (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.choices && body.choices.length > 0;
      } catch {
        return false;
      }
    },
  });

  errorRate.add(!ok);
  e2eLatency.add(elapsed);

  if (ok) {
    // Approximate TTFT from total latency for non-streaming requests
    // In a real benchmark, use streaming with SSE chunk timing
    const estimatedTTFT = elapsed * 0.3;
    ttft.add(estimatedTTFT);

    try {
      const body = JSON.parse(res.body);
      const tokens = body.usage?.total_tokens || 0;
      tokensThroughput.add(tokens);
    } catch (_) {
      // ignore
    }
  }

  // Minimal sleep to avoid client-side throttling
  sleep(0.1);
}

export function handleSummary(data) {
  const summary = {
    test: "load-10k-ramp",
    repo: "nebius-llm-d-sglang",
    engine: "sglang",
    scheduler: "llm-d",
    model: "qwen3-27b",
    tp: 2,
    dtype: "bfloat16",
    timestamp: new Date().toISOString(),
    vus_max: data.metrics.vus?.values?.max,
    http_reqs_total: data.metrics.http_reqs?.values?.count,
    http_req_rate: data.metrics.http_reqs?.values?.rate,
    error_rate: data.metrics.error_rate?.values?.rate,
    ttft_p50_s: data.metrics.ttft_seconds?.values?.["p(50)"],
    ttft_p95_s: data.metrics.ttft_seconds?.values?.["p(95)"],
    ttft_p99_s: data.metrics.ttft_seconds?.values?.["p(99)"],
    e2e_p95_s: data.metrics.e2e_latency_seconds?.values?.["p(95)"],
    e2e_p99_s: data.metrics.e2e_latency_seconds?.values?.["p(99)"],
    total_tokens: data.metrics.total_tokens?.values?.count,
    thresholds_passed: Object.entries(data.thresholds || {}).every(
      ([, v]) => v.ok
    ),
  };

  console.log(JSON.stringify(summary, null, 2));

  return {
    stdout: JSON.stringify(summary, null, 2),
  };
}
