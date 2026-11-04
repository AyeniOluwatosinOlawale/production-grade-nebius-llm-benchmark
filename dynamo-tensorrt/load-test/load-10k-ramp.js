import http from 'k6/http';
import { Trend, Counter } from 'k6/metrics';
import { check } from 'k6';

const ttftMs = new Trend('ttft_ms', true);
const tpotMs = new Trend('tpot_ms', true);
const tokensPerReq = new Trend('tokens_per_req');
const totalTokens = new Counter('total_tokens');

const BASE_URL = __ENV.BASE_URL || 'http://litellm-svc.llm-inference:4000';

const PROMPTS = [
  "Explain gradient descent in machine learning.",
  "What is the difference between TCP and UDP?",
  "Describe how transformers work in NLP.",
  "What are the main cloud computing service models?",
  "How does containerization differ from virtualization?",
];

export const options = {
  stages: [
    { duration: '5m',  target: 20  },
    { duration: '8m',  target: 150 },
    { duration: '10m', target: 150 },
    { duration: '7m',  target: 500 },
    { duration: '5m',  target: 0   },
  ],
  thresholds: {
    ttft_ms:           ['p95<3000'],
    http_req_duration: ['p95<15000'],
    http_req_failed:   ['rate<0.05'],
  },
};

export default function () {
  const prompt = PROMPTS[Math.floor(Math.random() * PROMPTS.length)];
  const startMs = Date.now();
  let firstTokenMs = null;
  let lastTokenMs = null;
  let tokenCount = 0;

  const res = http.post(
    `${BASE_URL}/v1/chat/completions`,
    JSON.stringify({
      model: 'qwen3-27b',
      messages: [{ role: 'user', content: prompt }],
      stream: true,
      max_tokens: 50,
    }),
    { headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' } }
  );

  check(res, { 'status 200': (r) => r.status === 200 });

  if (res.body) {
    res.body.split('\n').forEach(line => {
      if (line.startsWith('data: ') && !line.includes('[DONE]')) {
        const nowMs = Date.now();
        if (firstTokenMs === null) {
          firstTokenMs = nowMs;
          ttftMs.add(nowMs - startMs);
        } else if (lastTokenMs !== null) {
          tpotMs.add(nowMs - lastTokenMs);
        }
        lastTokenMs = nowMs;
        tokenCount++;
      }
    });
  }

  tokensPerReq.add(tokenCount);
  totalTokens.add(tokenCount);
}
