import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://litellm-svc.llm-inference:4000';

export const options = {
  vus: 10,
  duration: '1m',
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p95<15000'],
  },
};

export default function () {
  const payload = JSON.stringify({
    model: 'qwen3-27b',
    messages: [
      {
        role: 'user',
        content: 'What is the capital of France? Answer in one sentence.',
      },
    ],
    stream: false,
    max_tokens: 64,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    timeout: '30s',
  };

  const res = http.post(`${BASE_URL}/v1/chat/completions`, payload, params);

  check(res, {
    'status 200': (r) => r.status === 200,
    'has choices': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.choices && body.choices.length > 0;
      } catch (_) {
        return false;
      }
    },
  });

  sleep(1);
}
