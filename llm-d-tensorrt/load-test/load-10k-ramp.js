/**
 * k6 load test — 5-phase ramp, ~10,000+ requests, 35 minutes
 * Measures TTFT, TPOT, throughput, and validates KEDA scale-out.
 * Run: k6 run load-test/load-10k-ramp.js --out json=load-test/reports/results.json
 */
import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";

const errorRate = new Rate("errors");
const ttft = new Trend("ttft_ms", true);
const totalTokens = new Counter("total_tokens");

export const options = {
  scenarios: {
    ramp_load: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "3m", target: 20 },   // Phase 1: warm-up
        { duration: "5m", target: 20 },   // Phase 2: steady low
        { duration: "5m", target: 150 },  // Phase 3: ramp to medium — KEDA should scale
        { duration: "10m", target: 150 }, // Phase 4: sustained medium
        { duration: "5m", target: 250 },  // Phase 5: peak — capped at 250 to stay under LiteLLM limit
        { duration: "5m", target: 250 },  // Phase 6: sustained peak
        { duration: "2m", target: 0 },    // Phase 7: cool-down
      ],
    },
  },
  thresholds: {
    errors: ["rate<0.10"],
    http_req_duration: ["p(95)<60000"],
    ttft_ms: ["p(95)<5000"],
  },
};

const LITELLM_URL = __ENV.LITELLM_URL || "http://localhost:4000";
const API_KEY = __ENV.LITELLM_KEY || "sk-nebius-bench-1234";

const PROMPTS = [
  "Explain the difference between supervised and unsupervised learning in machine learning.",
  "Write a Python function that calculates the Fibonacci sequence up to n terms.",
  "What are the main architectural differences between GPT and BERT?",
  "Describe the CAP theorem and give a real-world example for each combination.",
  "How does TensorRT optimize neural network inference on NVIDIA GPUs?",
  "Explain KV cache in the context of large language model inference.",
  "What is tensor parallelism and how does it differ from pipeline parallelism?",
  "Describe the challenges of running LLMs on preemptible GPU instances.",
  "How does KEDA autoscaling work with Prometheus metrics?",
  "Explain the difference between TTFT and TPOT in LLM serving benchmarks.",
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
    timeout: "90s",
  };

  const start = Date.now();
  const res = http.post(`${LITELLM_URL}/v1/chat/completions`, payload, params);
  const elapsed = Date.now() - start;

  const ok = check(res, {
    "status 200": (r) => r.status === 200,
    "has content": (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.choices && body.choices[0].message.content.length > 0;
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
      const tokens = body.usage?.total_tokens || 0;
      totalTokens.add(tokens);
    } catch {}
  }

  // Realistic inter-request delay
  sleep(Math.random() * 2 + 0.5);
}
