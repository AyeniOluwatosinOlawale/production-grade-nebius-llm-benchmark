/**
 * k6 replica verification script
 * Runs alongside the load test to confirm KEDA scaled out TensorRT replicas.
 * Queries the Kubernetes API (or a metrics endpoint) to check replica count.
 * Run: k6 run load-test/verify-replicas.js
 */
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 1,
  duration: "35m",
  thresholds: {
    checks: ["rate>0.5"], // at least 50% of checks should see >=3 replicas during peak
  },
};

const PROMETHEUS_URL =
  __ENV.PROMETHEUS_URL || "http://localhost:9090";
const ENGINE_LABEL = __ENV.ENGINE_LABEL || "tensorrt-qwen3";
const MIN_REPLICAS_DURING_LOAD = parseInt(__ENV.MIN_REPLICAS || "3");

export default function () {
  // Query Prometheus for ready replica count
  const query = encodeURIComponent(
    `kube_deployment_status_replicas_available{namespace="llm-inference",deployment="${ENGINE_LABEL}"}`
  );

  const res = http.get(`${PROMETHEUS_URL}/api/v1/query?query=${query}`, {
    timeout: "10s",
  });

  let replicaCount = 0;

  if (res.status === 200) {
    try {
      const body = JSON.parse(res.body);
      const result = body.data?.result?.[0];
      if (result) {
        replicaCount = parseInt(result.value[1]);
      }
    } catch {}
  }

  check(replicaCount, {
    [`replicas >= ${MIN_REPLICAS_DURING_LOAD} (got ${replicaCount})`]: (r) =>
      r >= MIN_REPLICAS_DURING_LOAD,
  });

  console.log(
    `[verify-replicas] ${new Date().toISOString()} — ${ENGINE_LABEL} ready replicas: ${replicaCount}`
  );

  sleep(30); // check every 30 seconds
}
