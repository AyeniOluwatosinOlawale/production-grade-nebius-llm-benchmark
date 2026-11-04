#!/bin/bash
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:4000}"
ENGINE_LABEL="${ENGINE_LABEL:-sglang-decode}"
NAMESPACE="${NAMESPACE:-llm-inference}"
RESULTS_DIR="load-test/reports/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "=== nebius-dynamo-sglang -- Load Test | $BASE_URL ==="
k6 run -e BASE_URL="$BASE_URL" --out json="$RESULTS_DIR/smoke.json" load-test/smoke-test.js

(while true; do
  DECODE=$(kubectl get pods -n "$NAMESPACE" -l app=sglang-decode --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
  PREFILL=$(kubectl get pods -n "$NAMESPACE" -l app=sglang-prefill --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
  echo "[$(date -u +%H:%M:%S)] Decode: $DECODE | Prefill: $PREFILL"
  sleep 60
done) &
WATCHER_PID=$!

k6 run -e BASE_URL="$BASE_URL" \
  --out json="$RESULTS_DIR/load-10k.json" \
  --summary-export="$RESULTS_DIR/summary.json" \
  load-test/load-10k-ramp.js
LOAD_EXIT=$?

kill "$WATCHER_PID" 2>/dev/null || true

DECODE=$(kubectl get pods -n "$NAMESPACE" -l app=sglang-decode --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
echo "Final decode replicas: $DECODE"
[ "$DECODE" -ge 2 ] || { echo "ERROR: Expected >=2 decode replicas"; LOAD_EXIT=1; }

echo "=== Done. Results: $RESULTS_DIR/ ==="
exit "$LOAD_EXIT"
