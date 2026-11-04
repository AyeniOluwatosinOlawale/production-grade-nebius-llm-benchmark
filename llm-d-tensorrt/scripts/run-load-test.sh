#!/usr/bin/env bash
# Run the full load test suite for nebius-llm-d-tensorrt
# Requires: k6 installed (https://k6.io/docs/get-started/installation/)
set -euo pipefail

NAMESPACE="llm-inference"
REPORT_DIR="load-test/reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "${REPORT_DIR}"

# Resolve LiteLLM LoadBalancer IP
LITELLM_IP=$(kubectl get svc litellm -n "${NAMESPACE}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -z "${LITELLM_IP}" ]]; then
  LITELLM_IP=$(kubectl get svc litellm -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost")
fi

LITELLM_URL="http://${LITELLM_IP}:4000"
PROMETHEUS_URL="http://$(kubectl get svc prometheus-operated -n monitoring \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "localhost"):9090"

echo "==> LiteLLM URL: ${LITELLM_URL}"
echo "==> Prometheus URL: ${PROMETHEUS_URL}"
echo ""

echo "==> Step 1: Smoke test (2 min)..."
k6 run \
  -e LITELLM_URL="${LITELLM_URL}" \
  --out json="${REPORT_DIR}/smoke-${TIMESTAMP}.json" \
  load-test/smoke-test.js

echo ""
echo "==> Step 2: Full load test (35 min) + replica verification in background..."

# Start replica verification in background
k6 run \
  -e PROMETHEUS_URL="${PROMETHEUS_URL}" \
  -e ENGINE_LABEL="tensorrt-qwen3" \
  -e MIN_REPLICAS="3" \
  --out json="${REPORT_DIR}/replicas-${TIMESTAMP}.json" \
  load-test/verify-replicas.js &

VERIFY_PID=$!

# Run main load test
k6 run \
  -e LITELLM_URL="${LITELLM_URL}" \
  --out json="${REPORT_DIR}/load-${TIMESTAMP}.json" \
  load-test/load-10k-ramp.js

# Wait for replica verifier
wait ${VERIFY_PID} || true

echo ""
echo "==> Load test complete. Reports written to ${REPORT_DIR}/"
ls -lh "${REPORT_DIR}/"
