/**
 * k6 smoke test — 5 VUs for 2 minutes
 * Verifies the stack is healthy before the main load test.
 * Run: k6 run load-test/smoke-test.js
 */
import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const errorRate = new Rate("errors");
const ttft = new Trend("ttft_ms", true);

export const options = {
  vus: 5,
  duration: "2m",
  thresholds: {
    errors: ["rate<0.05"],
    http_req_duration: ["p(95)<30000"],
  },
};

const LITELLM_URL = __ENV.LITELLM_URL || "http://localhost:4000";
const API_KEY = __ENV.LITELLM_KEY || "sk-nebius-bench-1234";

export default function () {
  const payload = JSON.stringify({
    model: "qwen3-27b",
    messages: [
      {
        role: "user",
        content: "In one sentence, what is the capital of France?",
      },
    ],
    max_tokens: 64,
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
  const elapsed = Date.now() - start;

  const ok = check(res, {
    "status 200": (r) => r.status === 200,
    "has choices": (r) => {
      try {
        return JSON.parse(r.body).choices.length > 0;
      } catch {
        return false;
      }
    },
  });

  errorRate.add(!ok);
  if (ok) ttft.add(elapsed);

  sleep(1);
}
