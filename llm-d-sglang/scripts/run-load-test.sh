#!/usr/bin/env bash
# run-load-test.sh — Execute k6 load tests against nebius-llm-d-sglang
#
# Usage:
#   ./scripts/run-load-test.sh                 # defaults to smoke
#   ./scripts/run-load-test.sh smoke           # 10 VUs, 30s sanity check
#   ./scripts/run-load-test.sh ramp            # full 10k ramp test
#   ./scripts/run-load-test.sh verify          # replica monitor (non-k6)
#
# Environment overrides:
#   LITELLM_URL          default: http://localhost:4000 (assumes kubectl proxy)
#   LITELLM_API_KEY      default: sk-nebius-bench-1234
#   ENGINE_LABEL         default: sglang-qwen3
#   RESULTS_DIR          default: load-test/results
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TEST_TYPE="${1:-smoke}"
LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
LITELLM_API_KEY="${LITELLM_API_KEY:-sk-nebius-bench-1234}"
ENGINE_LABEL="${ENGINE_LABEL:-sglang-qwen3}"
RESULTS_DIR="${RESULTS_DIR:-${REPO_ROOT}/load-test/results}"

mkdir -p "${RESULTS_DIR}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "============================================================"
echo "  nebius-llm-d-sglang — Load Test: ${TEST_TYPE}"
echo "============================================================"
echo "  LiteLLM URL:  ${LITELLM_URL}"
echo "  Engine label: ${ENGINE_LABEL}"
echo "  Results dir:  ${RESULTS_DIR}"
echo ""

case "${TEST_TYPE}" in
  smoke)
    RESULT_FILE="${RESULTS_DIR}/smoke-${TIMESTAMP}.json"
    echo "==> Running smoke test (10 VUs, 30s)..."
    k6 run \
      --out "json=${RESULT_FILE}" \
      --env LITELLM_URL="${LITELLM_URL}" \
      --env LITELLM_API_KEY="${LITELLM_API_KEY}" \
      "${REPO_ROOT}/load-test/smoke-test.js"
    echo ""
    echo "==> Smoke test complete. Results: ${RESULT_FILE}"
    ;;

  ramp)
    RESULT_FILE="${RESULTS_DIR}/ramp-${TIMESTAMP}.json"
    echo "==> Running ramp test (0 → 100 VUs, ~20min)..."
    echo "    This will trigger KEDA autoscaling. Watch replicas in another terminal:"
    echo "    kubectl get pods -n llm-inference -l app=${ENGINE_LABEL} -w"
    echo ""
    k6 run \
      --out "json=${RESULT_FILE}" \
      --env LITELLM_URL="${LITELLM_URL}" \
      --env LITELLM_API_KEY="${LITELLM_API_KEY}" \
      "${REPO_ROOT}/load-test/load-10k-ramp.js"
    echo ""
    echo "==> Ramp test complete. Results: ${RESULT_FILE}"
    ;;

  verify)
    echo "==> Starting replica monitor (polls every 15s for 10min)..."
    echo "    Run this alongside a load test to observe autoscaling."
    echo ""
    ENGINE_LABEL="${ENGINE_LABEL}" \
      NAMESPACE="llm-inference" \
      POLL_INTERVAL_S="15" \
      DURATION_S="600" \
      node "${REPO_ROOT}/load-test/verify-replicas.js"
    ;;

  all)
    echo "==> Running smoke test first..."
    "${BASH_SOURCE[0]}" smoke

    echo ""
    echo "==> Starting replica monitor in background..."
    ENGINE_LABEL="${ENGINE_LABEL}" node "${REPO_ROOT}/load-test/verify-replicas.js" &
    MONITOR_PID=$!

    echo "==> Running ramp test..."
    "${BASH_SOURCE[0]}" ramp

    wait "${MONITOR_PID}" || true
    echo ""
    echo "==> All tests complete."
    ;;

  *)
    echo "ERROR: Unknown test type '${TEST_TYPE}'. Use: smoke | ramp | verify | all" >&2
    exit 1
    ;;
esac
