#!/bin/bash
# Curl-verify the Dynamo endpoint returns real inference tokens.
# MUST pass before running any benchmark.
set -euo pipefail

NAMESPACE="dynamo-vllm"
API_KEY="${API_KEY:-sk-benchmark}"

echo "=== Dynamo Endpoint Verification ==="
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

# Step 1: Check /v1/models via router directly
ROUTER_POD=$(kubectl get pod -n "$NAMESPACE" -l app=dynamo-router -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$ROUTER_POD" ]; then
  echo "--- Step 1: Router /v1/models ---"
  MODELS=$(kubectl exec -n "$NAMESPACE" "$ROUTER_POD" -- curl -s http://localhost:8080/v1/models 2>/dev/null)
  echo "$MODELS"
  if echo "$MODELS" | grep -q '"id"'; then
    echo "✓ Router sees models"
  else
    echo "✗ Router /v1/models is empty — workers not discovered. Run debug-router.sh"
    exit 1
  fi
  echo ""
fi

# Step 2: LiteLLM /health
echo "--- Step 2: LiteLLM health check ---"
HEALTH=$(curl -s --max-time 10 "${BASE_URL}/health" || echo "FAILED")
echo "$HEALTH"
echo ""

# Step 3: Real inference request (non-streaming)
echo "--- Step 3: Real inference request ---"
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
  echo "  Run: bash scripts/debug-router.sh"
  exit 1
fi
