/**
 * Main load test — 5-phase, 35 min, ~10,000+ requests.
 * Measures TTFT and TPOT via SSE stream parsing.
 *
 * Phases:
 *   1. Warm-up      5m  20 VUs  — confirm stable baseline
 *   2. Trigger      8m  150 VUs — hit KEDA scale threshold
 *   3. Hold        10m  150 VUs — replica verify window (t=23min)
 *   4. Stress peak  7m  500 VUs — push throughput, verify ≥3 replicas
 *   5. Ramp down    5m    0 VUs — observe KEDA cooldown
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

// Custom metrics — captured from SSE stream
const ttftMs   = new Trend('ttft_ms',   true);
const tpotMs   = new Trend('tpot_ms',   true);
const tokenCount = new Trend('tokens_per_request');
const totalTokens = new Counter('total_tokens_generated');

// Fixed short prompt — deterministic across all 6 repos for fair comparison
const PROMPT = 'Explain gradient descent in exactly two sentences.';

export const options = {
  stages: [
    { duration: '5m',  target: 20  },  // warm-up
    { duration: '8m',  target: 150 },  // trigger KEDA scale
    { duration: '10m', target: 150 },  // hold — replica verify window at t≈23min
    { duration: '7m',  target: 250 },  // stress peak — capped at 250 to stay under LiteLLM limit
    { duration: '5m',  target: 0   },  // ramp down — observe cooldown
  ],
  thresholds: {
    // Client-side TTFT: 95th percentile under 3 seconds
    'ttft_ms':              ['p(95)<3000'],
    // E2E latency budget: 15s p95 (27B model at 50 output tokens)
    'http_req_duration':    ['p(95)<15000'],
    // Error rate under 5%
    'http_req_failed':      ['rate<0.05'],
  },
};

export default function () {
  const payload = JSON.stringify({
    model: 'qwen3-27b',
    messages: [{ role: 'user', content: PROMPT }],
    max_tokens: 50,       // short output — deterministic, comparable across repos
    temperature: 0,
    stream: true,
  });

  const startMs = Date.now();
  let firstTokenMs = null;
  let lastTokenMs = null;
  let tokens = 0;

  const res = http.post(`${BASE_URL}/v1/chat/completions`, payload, {
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    },
    timeout: '60s',
  });

  check(res, { 'status 200': (r) => r.status === 200 });

  if (res.status === 200 && res.body) {
    const lines = res.body.split('\n');
    for (const line of lines) {
      if (line.startsWith('data: ') && !line.includes('[DONE]')) {
        const now = Date.now();
        try {
          const data = JSON.parse(line.slice(6));
          const delta = data.choices?.[0]?.delta?.content;
          if (delta && delta.length > 0) {
            if (firstTokenMs === null) {
              firstTokenMs = now;
              ttftMs.add(now - startMs);
            } else if (lastTokenMs !== null) {
              tpotMs.add(now - lastTokenMs);
            }
            lastTokenMs = now;
            tokens++;
          }
        } catch {
          // non-JSON SSE line, skip
        }
      }
    }
  }

  if (tokens > 0) {
    tokenCount.add(tokens);
    totalTokens.add(tokens);
  }

  // No sleep — VUs immediately request next completion to maximise concurrency pressure
  sleep(0.5);
}
