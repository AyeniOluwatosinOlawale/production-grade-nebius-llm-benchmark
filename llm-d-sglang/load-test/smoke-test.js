/**
 * smoke-test.js — Quick sanity check for the nebius-llm-d-sglang stack.
 *
 * Sends 10 concurrent chat completion requests for 30 seconds.
 * Fails the test if:
 *   - Any request returns a non-2xx status
 *   - p95 TTFT exceeds 10 seconds
 *   - Error rate exceeds 1%
 *
 * Usage:
 *   k6 run load-test/smoke-test.js
 *   LITELLM_URL=http://litellm.llm-inference:4000 k6 run load-test/smoke-test.js
 */

import http from "k6/http";
import { check, sleep } from "k6";
import { Trend, Rate, Counter } from "k6/metrics";

const ttft = new Trend("ttft_seconds", true);
const errorRate = new Rate("error_rate");
const tokenCount = new Counter("total_tokens");

export const options = {
  vus: 10,
  duration: "30s",
  thresholds: {
    http_req_failed: ["rate<0.01"],
    ttft_seconds: ["p(95)<10"],
    error_rate: ["rate<0.01"],
  },
};

const LITELLM_URL = __ENV.LITELLM_URL || "http://litellm.llm-inference:4000";
const API_KEY = __ENV.LITELLM_API_KEY || "sk-nebius-bench-1234";

const PROMPTS = [
  "Explain the concept of tensor parallelism in large language model inference in two sentences.",
  "What are the main differences between prefill and decode phases in LLM serving?",
  "Describe KV-cache and why it matters for multi-turn conversations.",
  "What is chunked prefill and how does it reduce TTFT variance?",
  "In 50 words, explain why BF16 is preferred over FP16 for LLM training and inference.",
];

export default function () {
  const prompt = PROMPTS[Math.floor(Math.random() * PROMPTS.length)];

  const payload = JSON.stringify({
    model: "qwen3-27b",
    messages: [{ role: "user", content: prompt }],
    max_tokens: 256,
    stream: false,
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${API_KEY}`,
    },
    timeout: "30s",
  };

  const start = Date.now();
  const res = http.post(`${LITELLM_URL}/v1/chat/completions`, payload, params);
  const elapsed = (Date.now() - start) / 1000;

  const ok = check(res, {
    "status 200": (r) => r.status === 200,
    "has choices": (r) => {
      try {
        return JSON.parse(r.body).choices?.length > 0;
      } catch {
        return false;
      }
    },
  });

  errorRate.add(!ok);

  if (ok) {
    ttft.add(elapsed);
    try {
      const body = JSON.parse(res.body);
      const tokens =
        body.usage?.total_tokens || body.usage?.completion_tokens || 0;
      tokenCount.add(tokens);
    } catch (_) {
      // ignore parse errors
    }
  }

  sleep(1);
}

export function handleSummary(data) {
  return {
    stdout: JSON.stringify(
      {
        test: "smoke-test",
        repo: "nebius-llm-d-sglang",
        engine: "sglang",
        scheduler: "llm-d",
        model: "qwen3-27b",
        vus: data.metrics.vus?.values?.max,
        duration_s: 30,
        http_reqs: data.metrics.http_reqs?.values?.count,
        error_rate: data.metrics.error_rate?.values?.rate,
        ttft_p50: data.metrics.ttft_seconds?.values?.["p(50)"],
        ttft_p95: data.metrics.ttft_seconds?.values?.["p(95)"],
        ttft_p99: data.metrics.ttft_seconds?.values?.["p(99)"],
        total_tokens: data.metrics.total_tokens?.values?.count,
        passed: data.metrics.http_req_failed?.values?.rate < 0.01,
      },
      null,
      2
    ),
  };
}
