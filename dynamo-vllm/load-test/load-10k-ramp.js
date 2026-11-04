/**
 * 5-phase 35-min load test with TTFT/TPOT streaming measurement.
 * Identical across all 6 benchmark repos for fair comparison.
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';
const ttftMs = new Trend('ttft_ms', true);
const tpotMs = new Trend('tpot_ms', true);
const tokenCount = new Trend('tokens_per_request');
const totalTokens = new Counter('total_tokens_generated');
const PROMPT = 'Explain gradient descent in exactly two sentences.';

export const options = {
  stages: [
    { duration: '5m',  target: 20  },
    { duration: '8m',  target: 150 },
    { duration: '10m', target: 150 },
    { duration: '7m',  target: 250 },  // stress peak — capped at 250 to stay under LiteLLM limit
    { duration: '5m',  target: 0   },
  ],
  thresholds: {
    'ttft_ms':           ['p(95)<3000'],
    'http_req_duration': ['p(95)<15000'],
    'http_req_failed':   ['rate<0.05'],
  },
};

export default function () {
  const payload = JSON.stringify({ model: 'qwen3-27b', messages: [{ role: 'user', content: PROMPT }], max_tokens: 50, temperature: 0, stream: true });
  const startMs = Date.now();
  let firstTokenMs = null;
  let lastTokenMs = null;
  let tokens = 0;

  const res = http.post(`${BASE_URL}/v1/chat/completions`, payload, {
    headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' },
    timeout: '60s',
  });

  check(res, { 'status 200': (r) => r.status === 200 });

  if (res.status === 200 && res.body) {
    for (const line of res.body.split('\n')) {
      if (line.startsWith('data: ') && !line.includes('[DONE]')) {
        const now = Date.now();
        try {
          const data = JSON.parse(line.slice(6));
          const delta = data.choices?.[0]?.delta?.content;
          if (delta && delta.length > 0) {
            if (firstTokenMs === null) { firstTokenMs = now; ttftMs.add(now - startMs); }
            else if (lastTokenMs !== null) { tpotMs.add(now - lastTokenMs); }
            lastTokenMs = now;
            tokens++;
          }
        } catch { /* non-JSON SSE */ }
      }
    }
  }
  if (tokens > 0) { tokenCount.add(tokens); totalTokens.add(tokens); }
  sleep(0.5);
}
