#!/bin/bash
# 5-phase 35-min load test with TTFT/TPOT measurement and replica verification
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
ENGINE_LABEL="${ENGINE_LABEL:-vllm-qwen3}"
NAMESPACE="${NAMESPACE:-llm-inference}"
RESULTS_DIR="load-test/reports/$(date +%Y%m%d-%H%M%S)"

mkdir -p "$RESULTS_DIR"

echo "================================================"
echo "  nebius-llm-d-vllm — Load Test"
echo "  Endpoint: $BASE_URL"
echo "  Results:  $RESULTS_DIR"
echo "================================================"

# --- Smoke test ---
echo ""
echo "==> Phase 0: Smoke test (5 VUs × 30s)..."
k6 run \
  -e BASE_URL="$BASE_URL" \
  --out json="$RESULTS_DIR/smoke.json" \
  load-test/smoke-test.js

echo "==> Smoke test passed. Starting 35-min load test..."

# --- Background replica watcher ---
(
  while true; do
    COUNT=$(kubectl get pods -n "$NAMESPACE" -l app="$ENGINE_LABEL" \
      --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
    echo "[$(date -u +%H:%M:%S)] Running replicas: $COUNT"
    sleep 60
  done
) &
WATCHER_PID=$!

# --- Main 35-min load test ---
echo ""
echo "==> Starting main load test (35 min, 5 phases)..."
k6 run \
  -e BASE_URL="$BASE_URL" \
  --out json="$RESULTS_DIR/load-10k.json" \
  --summary-export="$RESULTS_DIR/summary.json" \
  load-test/load-10k-ramp.js
LOAD_EXIT=$?

# Stop watcher
kill "$WATCHER_PID" 2>/dev/null || true

# --- Replica verification (at end of test) ---
echo ""
echo "==> Verifying replica count..."
RUNNING=$(kubectl get pods -n "$NAMESPACE" -l app="$ENGINE_LABEL" \
  --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
echo "Running replicas at test end: $RUNNING"

if [ "$RUNNING" -lt 2 ]; then
  echo "ERROR: Expected ≥2 replicas, got $RUNNING. KEDA may not have scaled."
  echo "Check: kubectl describe scaledobject -n $NAMESPACE"
  LOAD_EXIT=1
else
  echo "PASS: $RUNNING replicas running — KEDA scaled successfully."
fi

# --- Summary ---
echo ""
echo "================================================"
echo "  Load Test Complete"
echo "  Results: $RESULTS_DIR/"
echo "  Summary: cat $RESULTS_DIR/summary.json | jq '.metrics | {ttft_ms, tpot_ms, http_req_duration}'"
echo "================================================"

exit "$LOAD_EXIT"
