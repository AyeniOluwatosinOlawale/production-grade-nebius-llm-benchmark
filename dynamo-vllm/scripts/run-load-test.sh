#!/bin/bash
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:4000}"
ENGINE_LABEL="${ENGINE_LABEL:-vllm-decode}"
NAMESPACE="${NAMESPACE:-dynamo-vllm}"
RESULTS_DIR="load-test/reports/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "=== nebius-dynamo-vllm — Load Test | $BASE_URL ==="
k6 run -e BASE_URL="$BASE_URL" --out json="$RESULTS_DIR/smoke.json" load-test/smoke-test.js

(while true; do
  COUNT=$(kubectl get deployment -n "$NAMESPACE" "$ENGINE_LABEL" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  echo "[$(date -u +%H:%M:%S)] Ready replicas: ${COUNT:-0}"
  sleep 60
done) &
WATCHER_PID=$!

k6 run -e BASE_URL="$BASE_URL" \
  --out json="$RESULTS_DIR/load-10k.json" \
  --summary-export="$RESULTS_DIR/summary.json" \
  load-test/load-10k-ramp.js
LOAD_EXIT=$?

kill "$WATCHER_PID" 2>/dev/null || true

READY=$(kubectl get deployment -n "$NAMESPACE" "$ENGINE_LABEL" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
echo "Ready replicas at test end: $READY"

if [ "${READY:-0}" -lt 3 ]; then
  echo "WARN: Expected ≥3 ready replicas (KEDA scale-up), got ${READY:-0}."
  echo "  → KEDA may not have fired, or model is still loading."
  echo "  → Check: kubectl describe scaledobject -n $NAMESPACE"
  echo "  → Check: kubectl get hpa -n $NAMESPACE"
else
  echo "PASS: ${READY} ready replicas — KEDA scaled up successfully."
fi

echo "=== Done. Results: $RESULTS_DIR/ ==="
exit "$LOAD_EXIT"
