#!/bin/bash
# Export 7 KPIs from Prometheus before teardown.
# Output: results/<STACK_NAME>-<timestamp>.json  and  results/<STACK_NAME>-<timestamp>-summary.csv
set -euo pipefail

STACK_NAME="dynamo-tensorrt"
PROM_PORT=9191
PROM_NS="monitoring"
PROM_SVC="kube-prometheus-stack-prometheus"
RANGE="35m"
STEP="30s"
RESULTS_DIR="$(cd "$(dirname "$0")/.." && pwd)/results"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
OUT_JSON="$RESULTS_DIR/${STACK_NAME}-${TIMESTAMP}.json"
OUT_CSV="$RESULTS_DIR/${STACK_NAME}-${TIMESTAMP}-summary.csv"

mkdir -p "$RESULTS_DIR"

echo "==> Starting Prometheus port-forward on :${PROM_PORT}..."
kubectl port-forward -n "$PROM_NS" "svc/${PROM_SVC}" "${PROM_PORT}:9090" &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null" EXIT
sleep 3

BASE="http://localhost:${PROM_PORT}/api/v1"
END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START=$(date -u -d "-${RANGE}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v "-${RANGE}" +"%Y-%m-%dT%H:%M:%SZ")

query_range() {
  local metric="$1"
  curl -sf "${BASE}/query_range" \
    --data-urlencode "query=${metric}" \
    --data-urlencode "start=${START}" \
    --data-urlencode "end=${END}" \
    --data-urlencode "step=${STEP}"
}

query_instant() {
  local metric="$1"
  curl -sf "${BASE}/query" \
    --data-urlencode "query=${metric}"
}

echo "==> Querying 7 KPIs for stack: ${STACK_NAME}..."

TTFT_P95=$(query_range "llm:ttft_p95")
TTFT_P99=$(query_range "llm:ttft_p99")
TPOT=$(query_range "llm:tpot_p95")
TOKENS_PER_SEC=$(query_range "llm:tokens_per_second")
KV_CACHE=$(query_range "llm:kv_cache_util")
GPU_UTIL=$(query_range "avg(DCGM_FI_DEV_GPU_UTIL)")
THROUGHPUT=$(query_range "llm:request_throughput")
E2E_P95=$(query_range "llm:e2e_latency_p95")
E2E_P99=$(query_range "llm:e2e_latency_p99")
REPLICAS=$(query_range "kube_deployment_status_replicas_ready{deployment=~\"vllm|sglang|tensorrt\"}")

echo "==> Writing full timeseries to ${OUT_JSON}..."
cat > "$OUT_JSON" <<EOF
{
  "stack": "${STACK_NAME}",
  "exported_at": "${TIMESTAMP}",
  "range": "${RANGE}",
  "step": "${STEP}",
  "metrics": {
    "ttft_p95":       ${TTFT_P95},
    "ttft_p99":       ${TTFT_P99},
    "tpot_p95":       ${TPOT},
    "tokens_per_sec": ${TOKENS_PER_SEC},
    "kv_cache_util":  ${KV_CACHE},
    "gpu_util":       ${GPU_UTIL},
    "request_throughput": ${THROUGHPUT},
    "e2e_latency_p95": ${E2E_P95},
    "e2e_latency_p99": ${E2E_P99},
    "replica_count":  ${REPLICAS}
  }
}
EOF

echo "==> Computing summary averages..."

avg_of() {
  local data="$1"
  echo "$data" | python3 -c "
import sys, json, statistics
d = json.load(sys.stdin)
vals = [float(v[1]) for r in d.get('data',{}).get('result',[]) for v in r.get('values',[]) if v[1] not in ('NaN','Inf','+Inf','-Inf','')]
print(round(statistics.mean(vals), 4) if vals else 'N/A')
"
}

peak_of() {
  local data="$1"
  echo "$data" | python3 -c "
import sys, json
d = json.load(sys.stdin)
vals = [float(v[1]) for r in d.get('data',{}).get('result',[]) for v in r.get('values',[]) if v[1] not in ('NaN','Inf','+Inf','-Inf','')]
print(round(max(vals), 4) if vals else 'N/A')
"
}

echo "stack,ttft_p95_avg_s,ttft_p99_avg_s,tpot_p95_avg_s,tokens_per_sec_avg,kv_cache_avg_pct,gpu_util_avg_pct,throughput_avg_rps,e2e_p95_avg_s,e2e_p99_avg_s,gpu_util_peak_pct,throughput_peak_rps" > "$OUT_CSV"

echo "${STACK_NAME},$(avg_of "$TTFT_P95"),$(avg_of "$TTFT_P99"),$(avg_of "$TPOT"),$(avg_of "$TOKENS_PER_SEC"),$(avg_of "$KV_CACHE"),$(avg_of "$GPU_UTIL"),$(avg_of "$THROUGHPUT"),$(avg_of "$E2E_P95"),$(avg_of "$E2E_P99"),$(peak_of "$GPU_UTIL"),$(peak_of "$THROUGHPUT")" >> "$OUT_CSV"

echo ""
echo "==> Export complete."
echo "    JSON timeseries : $OUT_JSON"
echo "    CSV summary     : $OUT_CSV"
echo ""
cat "$OUT_CSV"
