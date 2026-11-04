/**
 * Smoke test — 5 VUs for 30s.
 * Confirms the LiteLLM endpoint is alive and returning valid responses.
 * Run before every load test.
 */
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

const PROMPT = 'Reply in one sentence: what is a large language model?';

export const options = {
  vus: 5,
  duration: '30s',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p95<30000'],
  },
};

export default function () {
  const payload = JSON.stringify({
    model: 'qwen3-27b',
    messages: [{ role: 'user', content: PROMPT }],
    max_tokens: 30,
    temperature: 0,
  });

  const res = http.post(`${BASE_URL}/v1/chat/completions`, payload, {
    headers: { 'Content-Type': 'application/json' },
    timeout: '60s',
  });

  check(res, {
    'status 200': (r) => r.status === 200,
    'has choices': (r) => {
      try {
        return JSON.parse(r.body).choices?.length > 0;
      } catch {
        return false;
      }
    },
    'has content': (r) => {
      try {
        return JSON.parse(r.body).choices[0].message?.content?.length > 0;
      } catch {
        return false;
      }
    },
  });

  sleep(1);
}
