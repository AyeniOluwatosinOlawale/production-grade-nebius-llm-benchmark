import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export const options = {
  vus: 5,
  duration: '2m',
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<30000'],
  },
};

const PAYLOAD = JSON.stringify({
  model: 'qwen3-27b',
  messages: [{ role: 'user', content: 'What is 2+2? Reply in one sentence.' }],
  max_tokens: 64,
  stream: false,
});

export default function () {
  const res = http.post(`${BASE_URL}/v1/chat/completions`, PAYLOAD, {
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer sk-nebius-bench-1234' },
    timeout: '60s',
  });
  check(res, {
    'status 200': (r) => r.status === 200,
    'has choices': (r) => {
      try { return JSON.parse(r.body).choices.length > 0; } catch { return false; }
    },
  });
  sleep(1);
}
