#!/usr/bin/env node
/**
 * verify-replicas.js — Check SGLang replica count during/after a load test.
 *
 * Polls the Kubernetes API (or kubectl proxy) for the sglang-qwen3 Deployment
 * and prints a table of replica counts at regular intervals.
 *
 * Usage:
 *   # With kubectl proxy running on port 8001:
 *   kubectl proxy &
 *   node load-test/verify-replicas.js
 *
 *   # Custom settings:
 *   KUBE_API=http://localhost:8001 \
 *   ENGINE_LABEL=sglang-qwen3 \
 *   NAMESPACE=llm-inference \
 *   POLL_INTERVAL_S=15 \
 *   DURATION_S=600 \
 *   node load-test/verify-replicas.js
 */

const http = require("http");
const https = require("https");

const KUBE_API = process.env.KUBE_API || "http://localhost:8001";
const NAMESPACE = process.env.NAMESPACE || "llm-inference";
const ENGINE_LABEL = process.env.ENGINE_LABEL || "sglang-qwen3";
const DEPLOYMENT_NAME = process.env.DEPLOYMENT_NAME || ENGINE_LABEL;
const POLL_INTERVAL_S = parseInt(process.env.POLL_INTERVAL_S || "15", 10);
const DURATION_S = parseInt(process.env.DURATION_S || "600", 10);

const DEPLOY_PATH = `/apis/apps/v1/namespaces/${NAMESPACE}/deployments/${DEPLOYMENT_NAME}`;

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("https") ? https : http;
    client
      .get(url, (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(new Error(`Failed to parse response: ${data.slice(0, 200)}`));
          }
        });
      })
      .on("error", reject);
  });
}

async function getReplicaStatus() {
  const url = `${KUBE_API}${DEPLOY_PATH}`;
  const data = await fetchJson(url);

  const spec = data.spec?.replicas ?? "?";
  const desired = data.status?.replicas ?? 0;
  const ready = data.status?.readyReplicas ?? 0;
  const available = data.status?.availableReplicas ?? 0;
  const updated = data.status?.updatedReplicas ?? 0;

  return { spec, desired, ready, available, updated };
}

async function getHPAStatus() {
  const url = `${KUBE_API}/apis/keda.sh/v1alpha1/namespaces/${NAMESPACE}/scaledobjects/${ENGINE_LABEL}-scaledobject`;
  try {
    const data = await fetchJson(url);
    return {
      minReplicas: data.spec?.minReplicaCount ?? "?",
      maxReplicas: data.spec?.maxReplicaCount ?? "?",
      currentMetric: data.status?.externalMetricNames?.join(", ") ?? "unknown",
    };
  } catch {
    return null;
  }
}

function printHeader() {
  console.log(
    "\n" +
      "=".repeat(90) +
      "\n" +
      `  Replica Monitor — ${ENGINE_LABEL} in ${NAMESPACE}\n` +
      `  Polling every ${POLL_INTERVAL_S}s for ${DURATION_S}s\n` +
      "=".repeat(90)
  );
  console.log(
    "  Timestamp".padEnd(26) +
      "Spec".padStart(6) +
      "Desired".padStart(10) +
      "Ready".padStart(8) +
      "Available".padStart(12) +
      "Updated".padStart(10)
  );
  console.log("-".repeat(90));
}

async function main() {
  printHeader();

  const hpa = await getHPAStatus();
  if (hpa) {
    console.log(
      `  KEDA ScaledObject: min=${hpa.minReplicas} max=${hpa.maxReplicas} metrics=[${hpa.currentMetric}]\n`
    );
  }

  const results = [];
  const iterations = Math.ceil(DURATION_S / POLL_INTERVAL_S);

  for (let i = 0; i < iterations; i++) {
    try {
      const status = await getReplicaStatus();
      const ts = new Date().toISOString();
      results.push({ ts, ...status });

      const scalingIndicator =
        status.ready < status.spec
          ? " [SCALING UP]"
          : status.desired < status.spec
          ? " [SCALING DOWN]"
          : "";

      console.log(
        `  ${ts}` +
          String(status.spec).padStart(6) +
          String(status.desired).padStart(10) +
          String(status.ready).padStart(8) +
          String(status.available).padStart(12) +
          String(status.updated).padStart(10) +
          scalingIndicator
      );
    } catch (err) {
      console.error(`  [ERROR] ${new Date().toISOString()} — ${err.message}`);
    }

    if (i < iterations - 1) {
      await new Promise((r) => setTimeout(r, POLL_INTERVAL_S * 1000));
    }
  }

  // Summary
  const readyValues = results.map((r) => r.ready).filter((v) => typeof v === "number");
  const maxReady = Math.max(...readyValues);
  const minReady = Math.min(...readyValues);
  const avgReady = readyValues.reduce((a, b) => a + b, 0) / readyValues.length;

  console.log("\n" + "=".repeat(90));
  console.log("  Replica Summary");
  console.log("=".repeat(90));
  console.log(`  Engine:          ${ENGINE_LABEL}`);
  console.log(`  Namespace:       ${NAMESPACE}`);
  console.log(`  Observations:    ${readyValues.length}`);
  console.log(`  Min ready:       ${minReady}`);
  console.log(`  Max ready:       ${maxReady}  ← peak autoscale`);
  console.log(`  Avg ready:       ${avgReady.toFixed(1)}`);
  console.log(
    `  Scale-out fired: ${maxReady > minReady ? "YES (" + minReady + " → " + maxReady + ")" : "NO"}`
  );
  console.log("=".repeat(90) + "\n");

  // Exit non-zero if replicas never scaled above min
  if (maxReady <= 2) {
    console.warn(
      "  WARNING: Replicas never exceeded minimum (2). KEDA may not have triggered."
    );
    process.exit(1);
  }

  process.exit(0);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
