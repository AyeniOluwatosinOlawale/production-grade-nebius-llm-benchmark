import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

const tokensTrend = new Trend('tokens_per_request');
const totalTokens = new Counter('total_tokens_generated');

export const options = {
  scenarios: {
    ramp_load: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '5m',  target: 10  },
        { duration: '10m', target: 50  },
        { duration: '15m', target: 100 },
        { duration: '10m', target: 200 },
        { duration: '10m', target: 200 },
        { duration: '5m',  target: 0   },
      ],
    },
  },
  thresholds: {
    http_req_failed:   ['rate<0.05'],
    http_req_duration: ['p(95)<60000', 'p(99)<90000'],
  },
};

const PROMPTS = [
  'Explain transformer architecture in 3 sentences.',
  'What are the key differences between supervised and unsupervised learning?',
  'Describe the attention mechanism in neural networks.',
  'What is gradient descent and how does it work?',
  'Explain the concept of overfitting in machine learning.',
];

export default function () {
  const prompt = PROMPTS[Math.floor(Math.random() * PROMPTS.length)];
  const payload = JSON.stringify({
    model: 'qwen3-27b',
    messages: [{ role: 'user', content: prompt }],
    max_tokens: 256,
    stream: false,
  });

  const res = http.post(`${BASE_URL}/v1/chat/completions`, payload, {
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer sk-nebius-bench-1234' },
    timeout: '120s',
  });

  const ok = check(res, {
    'status 200':   (r) => r.status === 200,
    'has choices':  (r) => { try { return JSON.parse(r.body).choices.length > 0; } catch { return false; } },
  });

  if (ok) {
    try {
      const body = JSON.parse(res.body);
      const tokens = body.usage?.completion_tokens || 0;
      tokensTrend.add(tokens);
      totalTokens.add(tokens);
    } catch (_) {}
  }

  sleep(Math.random() * 2 + 0.5);
}
