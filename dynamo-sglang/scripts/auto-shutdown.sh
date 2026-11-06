#!/bin/bash
# Auto-shutdown: waits for benchmark PID to finish, saves logs to GitHub, deletes GPU node group.
# Usage: bash scripts/auto-shutdown.sh <k6-pid> <node-group-id> [log-file]
set -euo pipefail

BENCH_PID="${1:-}"
NODE_GROUP_ID="${2:-mk8snodegroup-e00rpbc6xtamswtfdw}"
LOG_FILE="${3:-/tmp/dynamo-sglang-benchmark.log}"
REPO="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"

if [ -z "$BENCH_PID" ]; then
  echo "Usage: bash auto-shutdown.sh <k6-pid> <node-group-id> [log-file]"
  exit 1
fi

echo "[$(date +%T)] Watching benchmark PID $BENCH_PID..."
while kill -0 "$BENCH_PID" 2>/dev/null; do sleep 15; done

echo "[$(date +%T)] Benchmark done. Saving logs..."
FINAL_LOG="$REPO/results/logs/dynamo-sglang-final-$(date +%Y%m%d-%H%M%S).log"
cp "$LOG_FILE" "$FINAL_LOG"

cd "$REPO"
ITERS=$(grep -oE "[0-9]+ complete" "$LOG_FILE" | tail -1 | grep -oE "[0-9]+" || echo "unknown")
git add -f "$FINAL_LOG"
git commit -m "chore: save dynamo-sglang final benchmark log — ${ITERS} iterations"
git push origin main
echo "[$(date +%T)] Pushed to GitHub."

echo "[$(date +%T)] Deleting GPU node group $NODE_GROUP_ID..."
~/.nebius/bin/nebius mk8s node-group delete --id "$NODE_GROUP_ID"
echo "[$(date +%T)] Done. Billing stopped."
