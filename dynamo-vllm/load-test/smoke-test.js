import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export const options = {
  vus: 5,
  duration: '30s',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p95<30000'],
  },
};

export default function () {
  const res = http.post(`${BASE_URL}/v1/chat/completions`,
    JSON.stringify({ model: 'qwen3-27b', messages: [{ role: 'user', content: 'Reply in one sentence: what is a large language model?' }], max_tokens: 30, temperature: 0 }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '60s' }
  );
  check(res, {
    'status 200': (r) => r.status === 200,
    'has choices': (r) => { try { return JSON.parse(r.body).choices?.length > 0; } catch { return false; } },
  });
  sleep(1);
}
