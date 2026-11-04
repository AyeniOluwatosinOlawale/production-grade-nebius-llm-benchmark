/**
 * Mixed-workload load test — 4 workload types, 5 phases, ~35 min.
 *
 * Stresses BOTH concurrency AND context window length simultaneously.
 * Each scenario runs independently with its own VU ramp.
 *
 * Workload types:
 *   short   ~10 input tokens  /  50 output  — latency baseline, max concurrency
 *   medium  ~500 input tokens / 500 output  — typical chat / RAG retrieval
 *   long    ~2000 input       / 1000 output — document summarisation
 *   context ~8000 input       / 2000 output — KV-cache exhaustion stress
 *
 * Phase design (total VUs across all scenarios):
 *   0–5m    warm-up      20 VUs  short only         — confirm baseline
 *   5–13m   KEDA trigger 140 VUs short+medium+long  — saturate 2 replicas
 *   13–23m  hold         140 VUs same mix            — new pods load model
 *   23–30m  context peak 150 VUs + context stress   — KV-cache pressure
 *   30–35m  ramp-down      0 VUs                    — KEDA cooldown
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

// ── Per-workload TTFT metrics ─────────────────────────────────────────────────
const ttft   = { short: new Trend('ttft_short_ms',   true),
                 medium: new Trend('ttft_medium_ms',  true),
                 long:   new Trend('ttft_long_ms',    true),
                 context:new Trend('ttft_context_ms', true) };

const tpot   = { short: new Trend('tpot_short_ms',   true),
                 medium: new Trend('tpot_medium_ms',  true),
                 long:   new Trend('tpot_long_ms',    true),
                 context:new Trend('tpot_context_ms', true) };

const totalTokens = new Counter('total_tokens_generated');

// ── Prompts calibrated to target token lengths ────────────────────────────────
// English text averages ~1.3 tokens/word; Qwen3 tokenizer is similar.

const PROMPTS = {
  // ~10 input tokens, 50 output
  short: {
    messages: [{ role: 'user', content: 'Explain gradient descent in exactly two sentences.' }],
    max_tokens: 50,
  },

  // ~500 input tokens (~2000 chars), 500 output
  medium: {
    messages: [
      {
        role: 'system',
        content: 'You are a helpful technical assistant. Answer clearly and concisely.',
      },
      {
        role: 'user',
        content: `You are given the following passage about machine learning optimisation. Read it carefully and summarise the key points in 500 words.\n\n` +
          `Stochastic gradient descent (SGD) is an iterative method for optimising an objective function with suitable smoothness properties. ` +
          `It can be regarded as a stochastic approximation of gradient descent optimisation, since it replaces the actual gradient (calculated from the entire data set) ` +
          `by an estimate thereof (calculated from a randomly selected subset of the data). ` +
          `Especially in high-dimensional optimisation problems this reduces the very high computational burden, achieving faster iterations in exchange for a lower convergence rate. ` +
          `The convergence of SGD has been studied extensively for convex problems. Many improvements and variants have been proposed and are used in practice for deep neural networks. ` +
          `Adam (Adaptive Moment Estimation) is an algorithm for first-order gradient-based optimisation of stochastic objective functions, based on adaptive estimates of lower-order moments. ` +
          `The method is straightforward to implement, is computationally efficient, has little memory requirement, is invariant to diagonal rescaling of gradients, ` +
          `and is well suited for problems that are large in terms of data and parameters. ` +
          `RMSprop is a gradient-based optimisation technique used in training neural networks. ` +
          `It was proposed by Geoffrey Hinton in his neural networks course at Coursera. ` +
          `RMSprop divides the learning rate for a weight by a running average of the magnitudes of recent gradients for that weight. ` +
          `Momentum is a method that helps accelerate SGD in the relevant direction and dampens oscillations. ` +
          `It does this by adding a fraction of the update vector of the past time step to the current update vector. ` +
          `Learning rate scheduling refers to changing the learning rate during training. ` +
          `A fixed learning rate can lead to slow convergence or oscillation around the minimum. ` +
          `Common schedules include step decay, exponential decay, and cosine annealing. ` +
          `Batch normalisation is a technique for training very deep neural networks that standardises the inputs to a layer for each mini-batch. ` +
          `This has the effect of stabilising the learning process and dramatically reducing the number of training epochs required to train deep networks. ` +
          `Dropout is a regularisation technique for reducing overfitting in neural networks. ` +
          `The technique temporarily drops units (along with their connections) from the neural network during training. ` +
          `Weight initialisation strategies such as Xavier and He initialisation help prevent vanishing and exploding gradients in deep networks.`,
      },
    ],
    max_tokens: 500,
  },

  // ~2000 input tokens (~8000 chars), 1000 output
  long: {
    messages: [
      {
        role: 'system',
        content: 'You are an expert technical writer. Produce detailed, accurate documentation.',
      },
      {
        role: 'user',
        content: `You are given a detailed technical document about transformer architecture and attention mechanisms. ` +
          `Write a comprehensive technical summary covering: (1) the core attention mechanism, (2) multi-head attention, ` +
          `(3) positional encodings, (4) feed-forward sublayers, and (5) training considerations. Target length: 1000 words.\n\n` +
          `DOCUMENT:\n\n` +
          `The Transformer is a deep learning architecture that relies entirely on a self-attention mechanism to draw global dependencies between input and output, ` +
          `dispensing with recurrence and convolutions entirely. The Transformer was proposed in the paper "Attention Is All You Need" by Vaswani et al. in 2017. ` +
          `Since its introduction, the Transformer has become the dominant architecture in natural language processing and has been extended to computer vision, audio, and other domains.\n\n` +
          `The core building block of the Transformer is the scaled dot-product attention mechanism. ` +
          `Given queries Q, keys K, and values V, attention is computed as: Attention(Q,K,V) = softmax(QK^T / sqrt(d_k)) V, ` +
          `where d_k is the dimensionality of the key vectors. The scaling factor 1/sqrt(d_k) prevents the dot products from growing large in magnitude, ` +
          `which would push the softmax into regions with extremely small gradients.\n\n` +
          `Multi-head attention allows the model to jointly attend to information from different representation subspaces at different positions. ` +
          `Instead of performing a single attention function with d_model-dimensional keys, values, and queries, it is beneficial to linearly project the queries, ` +
          `keys, and values h times with different, learned linear projections to d_k, d_k, and d_v dimensions, respectively. ` +
          `On each of these projected versions of queries, keys, and values, the attention function is performed in parallel, yielding d_v-dimensional output values. ` +
          `These are concatenated and once again projected, resulting in the final values.\n\n` +
          `Positional encodings are added to the input embeddings at the bottom of the encoder and decoder stacks. ` +
          `They have the same dimension d_model as the embeddings so that the two can be summed. ` +
          `The original Transformer uses sine and cosine functions of different frequencies: ` +
          `PE(pos, 2i) = sin(pos / 10000^(2i/d_model)), PE(pos, 2i+1) = cos(pos / 10000^(2i/d_model)). ` +
          `This allows the model to attend by relative positions since PE(pos+k) can be represented as a linear function of PE(pos). ` +
          `Many modern transformers use learned positional embeddings or rotary positional embeddings (RoPE) instead.\n\n` +
          `Each encoder layer contains two sublayers: a multi-head self-attention mechanism and a position-wise fully connected feed-forward network. ` +
          `A residual connection is employed around each of the two sublayers, followed by layer normalisation. ` +
          `The feed-forward network consists of two linear transformations with a ReLU or GELU activation in between: FFN(x) = max(0, xW_1 + b_1)W_2 + b_2. ` +
          `The dimensionality of the inner layer is typically 4× the model dimension, e.g., d_ff = 4096 for d_model = 1024.\n\n` +
          `The decoder is similar to the encoder but inserts a third sublayer performing multi-head attention over the output of the encoder stack. ` +
          `The self-attention sublayer in the decoder is modified to prevent positions from attending to subsequent positions. ` +
          `This masking, combined with the fact that the output embeddings are offset by one position, ensures that the predictions for position i can only depend on the known outputs at positions less than i.\n\n` +
          `Training transformers requires careful attention to learning rate schedules, gradient clipping, and weight initialisation. ` +
          `The original paper uses the Adam optimiser with beta_1=0.9, beta_2=0.98, epsilon=10^-9. ` +
          `A custom learning rate schedule is used: lrate = d_model^(-0.5) × min(step^(-0.5), step × warmup_steps^(-1.5)), ` +
          `which increases the learning rate linearly for the first warmup_steps training steps and decreases it thereafter proportionally to the inverse square root of the step number. ` +
          `Dropout is applied to the output of each sublayer, the sums of the embeddings and positional encodings in both encoder and decoder stacks.\n\n` +
          `Large language models based on the transformer architecture include GPT series (OpenAI), BERT (Google), T5 (Google), LLaMA (Meta), Qwen (Alibaba), and many others. ` +
          `These models scale the transformer architecture to billions of parameters and are trained on vast corpora of text. ` +
          `Key innovations include: grouped query attention (GQA) to reduce KV-cache memory, sliding window attention to handle long contexts, ` +
          `mixture of experts (MoE) to increase model capacity without proportional compute increase, and flash attention for memory-efficient exact attention computation. ` +
          `Quantisation techniques such as GPTQ, AWQ, and bitsandbytes allow these large models to be served on fewer GPUs by reducing weight precision from FP16 to INT8 or INT4.`,
      },
    ],
    max_tokens: 1000,
  },

  // ~8000 input tokens (~32000 chars), 2000 output — KV-cache exhaustion
  context: {
    messages: [
      {
        role: 'system',
        content: 'You are a senior software architect. Provide detailed, production-ready recommendations.',
      },
      {
        role: 'user',
        content: `You are reviewing a large codebase for a distributed inference serving system. ` +
          `Below is an extensive technical specification and design document. ` +
          `After reading it, produce a 2000-word architectural review covering: ` +
          `(1) scalability bottlenecks, (2) fault tolerance gaps, (3) observability recommendations, ` +
          `(4) security concerns, and (5) performance optimisation opportunities.\n\n` +
          `SPECIFICATION:\n\n` +
          // Repeat a long technical block to reach ~8000 tokens (~32000 chars)
          `${'The distributed inference serving system is designed to handle large language model inference at scale across multiple GPU nodes. ' +
          'The system architecture consists of three main layers: the request routing layer, the inference execution layer, and the monitoring and observability layer. ' +
          'The request routing layer receives incoming HTTP requests from clients and routes them to available inference workers based on current load, KV-cache locality, ' +
          'and hardware capabilities. The router maintains a real-time view of all worker states including GPU memory utilisation, active request counts, ' +
          'and KV-cache block availability. Requests are dispatched using a combination of shortest-queue-first and cache-aware routing strategies to maximise throughput ' +
          'while minimising time-to-first-token latency. The inference execution layer consists of multiple worker pods each running a single model shard or full model replica. ' +
          'Workers use tensor parallelism to distribute model weights across multiple GPUs within a node, and optionally pipeline parallelism across nodes for very large models. ' +
          'Each worker exposes an OpenAI-compatible HTTP API and a gRPC interface for internal communication with the router. ' +
          'Workers implement continuous batching to process multiple requests simultaneously, dynamically grouping decode steps across different sequence lengths. ' +
          'The KV-cache manager allocates GPU memory in fixed-size blocks and implements a paged attention mechanism to handle variable-length sequences efficiently. ' +
          'When GPU memory pressure is high, the cache manager implements preemption policies including recomputation and swapping to CPU memory. ' +
          'The monitoring layer collects metrics from all system components via Prometheus scraping and exports them to a centralised Grafana dashboard. ' +
          'Key metrics include TTFT, TPOT, tokens per second, KV-cache utilisation, GPU memory usage, power consumption, and request queue depths. ' +
          'The system uses KEDA for horizontal pod autoscaling based on Prometheus metrics, with custom scale triggers for queue depth and GPU utilisation. ' +
          'Deployment is managed via Helm charts on Kubernetes with preemptible GPU nodes to reduce costs. ' +
          'The system supports multiple inference backends including vLLM, SGLang, and TensorRT-LLM, abstracted behind a unified LiteLLM proxy layer. '.repeat(12)}`,
      },
    ],
    max_tokens: 2000,
  },
};

// ── k6 scenario options ───────────────────────────────────────────────────────
export const options = {
  scenarios: {
    // Short: high-concurrency latency baseline — runs full 35 min
    short_workload: {
      executor: 'ramping-vus',
      exec: 'shortWorkload',
      stages: [
        { duration: '5m',  target: 20  },  // warm-up
        { duration: '8m',  target: 80  },  // ramp to trigger KEDA
        { duration: '10m', target: 80  },  // hold — model loading window
        { duration: '7m',  target: 100 },  // peak concurrency
        { duration: '5m',  target: 0   },  // ramp down
      ],
    },

    // Medium: chat/RAG workload — starts at t=5m
    medium_workload: {
      executor: 'ramping-vus',
      exec: 'mediumWorkload',
      startTime: '5m',
      stages: [
        { duration: '3m',  target: 40  },  // ramp
        { duration: '15m', target: 40  },  // hold through KEDA verify window
        { duration: '7m',  target: 60  },  // peak
        { duration: '5m',  target: 0   },  // ramp down
      ],
    },

    // Long: document summarisation — starts at t=5m
    long_workload: {
      executor: 'ramping-vus',
      exec: 'longWorkload',
      startTime: '5m',
      stages: [
        { duration: '3m',  target: 20  },  // ramp
        { duration: '15m', target: 20  },  // hold
        { duration: '7m',  target: 20  },  // same — long requests limit safe concurrency
        { duration: '5m',  target: 0   },  // ramp down
      ],
    },

    // Context stress: KV-cache exhaustion — starts at t=23m (peak phase only)
    context_stress: {
      executor: 'ramping-vus',
      exec: 'contextWorkload',
      startTime: '23m',
      stages: [
        { duration: '2m',  target: 10  },  // ramp — only 10 VUs; 8k tokens each = huge KV pressure
        { duration: '5m',  target: 10  },  // hold
        { duration: '5m',  target: 0   },  // ramp down
      ],
    },
  },

  thresholds: {
    // Short workload: strictest latency budget
    'ttft_short_ms':          ['p(95)<3000'],
    // Medium workload
    'ttft_medium_ms':         ['p(95)<8000'],
    // Long workload
    'ttft_long_ms':           ['p(95)<20000'],
    // Context stress: very relaxed — 8k token prefill takes time
    'ttft_context_ms':        ['p(95)<45000'],
    // Global error rate
    'http_req_failed':        ['rate<0.05'],
    // Global E2E latency (driven by context workload at peak)
    'http_req_duration':      ['p(95)<120000'],
  },
};

// ── SSE stream parser ─────────────────────────────────────────────────────────
function parseStream(res, ttftTrend, tpotTrend, startMs) {
  let firstTokenMs = null;
  let lastTokenMs  = null;
  let tokens = 0;

  if (res.status !== 200 || !res.body) return 0;

  const lines = res.body.split('\n');
  for (const line of lines) {
    if (!line.startsWith('data: ') || line.includes('[DONE]')) continue;
    try {
      const data  = JSON.parse(line.slice(6));
      const delta = data.choices?.[0]?.delta?.content;
      if (delta && delta.length > 0) {
        const now = Date.now();
        if (firstTokenMs === null) {
          firstTokenMs = now;
          ttftTrend.add(now - startMs);
        } else if (lastTokenMs !== null) {
          tpotTrend.add(now - lastTokenMs);
        }
        lastTokenMs = now;
        tokens++;
      }
    } catch { /* non-JSON SSE line */ }
  }
  return tokens;
}

function sendRequest(workloadKey, sleepSecs) {
  const cfg     = PROMPTS[workloadKey];
  const startMs = Date.now();

  const res = http.post(
    `${BASE_URL}/v1/chat/completions`,
    JSON.stringify({
      model: 'qwen3-27b',
      messages: cfg.messages,
      max_tokens: cfg.max_tokens,
      temperature: 0,
      stream: true,
    }),
    {
      headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' },
      timeout: '180s',
    }
  );

  check(res, { [`${workloadKey} status 200`]: (r) => r.status === 200 });

  const n = parseStream(res, ttft[workloadKey], tpot[workloadKey], startMs);
  if (n > 0) totalTokens.add(n);

  sleep(sleepSecs);
}

// ── Scenario exec functions ───────────────────────────────────────────────────
export function shortWorkload()   { sendRequest('short',   0.5); }
export function mediumWorkload()  { sendRequest('medium',  1.0); }
export function longWorkload()    { sendRequest('long',    2.0); }
export function contextWorkload() { sendRequest('context', 3.0); }
