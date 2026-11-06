#!/bin/bash
# Curl-verify the llm-d TensorRT endpoint returns real inference tokens.
# MUST pass before running any benchmark.
set -euo pipefail

NAMESPACE="llm-inference"
API_KEY="${API_KEY:-sk-benchmark}"

echo "=== llm-d TensorRT Endpoint Verification ==="
echo ""

# Get LiteLLM external IP
LB_IP=$(kubectl get svc litellm -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -z "$LB_IP" ]; then
  echo "ERROR: LiteLLM LoadBalancer IP not ready yet. Run: kubectl get svc -n $NAMESPACE"
  exit 1
fi
BASE_URL="http://${LB_IP}:4000"
echo "LiteLLM endpoint: $BASE_URL"
echo ""

# Step 1: Check TensorRT engine /v1/models directly
ENGINE_POD=$(kubectl get pod -n "$NAMESPACE" -l app=tensorrt-qwen3 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$ENGINE_POD" ]; then
  echo "--- Step 1: TensorRT engine /v1/models ---"
  MODELS=$(kubectl exec -n "$NAMESPACE" "$ENGINE_POD" -- curl -s http://localhost:8000/v1/models 2>/dev/null)
  echo "$MODELS"
  if echo "$MODELS" | grep -q '"id"'; then
    echo "✓ TensorRT engine serving models"
  else
    echo "✗ TensorRT /v1/models is empty — engine not ready yet"
    echo "  TensorRT model compilation can take 20-40 min on first run."
    echo "  Check logs: kubectl logs -n $NAMESPACE $ENGINE_POD --tail=50"
    exit 1
  fi
  echo ""
fi

# Step 2: Check llm-d InferencePool / gateway
GATEWAY_SVC=$(kubectl get svc llmd-gateway -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
if [ -n "$GATEWAY_SVC" ]; then
  echo "--- Step 2: llm-d gateway /v1/models ---"
  GW_MODELS=$(curl -s --max-time 10 "http://${GATEWAY_SVC}:80/v1/models" 2>/dev/null || echo "FAILED")
  echo "$GW_MODELS"
  if echo "$GW_MODELS" | grep -q '"id"'; then
    echo "✓ llm-d gateway sees models"
  else
    echo "WARN: gateway /v1/models empty — InferencePool may still be syncing"
  fi
  echo ""
fi

# Step 3: LiteLLM /health
echo "--- Step 3: LiteLLM health check ---"
HEALTH=$(curl -s --max-time 10 "${BASE_URL}/health" || echo "FAILED")
echo "$HEALTH"
echo ""

# Step 4: Real inference request (non-streaming)
echo "--- Step 4: Real inference request ---"
RESPONSE=$(curl -s --max-time 60 "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-27b",
    "messages": [{"role": "user", "content": "Say the word hello only."}],
    "max_tokens": 10,
    "stream": false
  }')

echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
echo ""

# Validate response contains real content
CONTENT=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null || echo "")
if [ -n "$CONTENT" ]; then
  echo "✓ REAL TOKENS RECEIVED: \"$CONTENT\""
  echo ""
  echo "========================================"
  echo "  Endpoint verified. Safe to benchmark."
  echo "========================================"
else
  echo "✗ No tokens in response. Do NOT run benchmark."
  echo "  Check TensorRT logs: kubectl logs -n $NAMESPACE -l app=tensorrt-qwen3 --tail=50"
  exit 1
fi
