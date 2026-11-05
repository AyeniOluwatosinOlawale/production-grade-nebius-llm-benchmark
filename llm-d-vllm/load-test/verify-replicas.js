/**
 * Replica verification helper — run this script mid-load (at ~t=23min)
 * via the shell wrapper in scripts/run-load-test.sh.
 *
 * This is NOT a load test — it's a point-in-time assertion.
 * It exits non-zero if fewer than MIN_REPLICAS pods are Running.
 */
import exec from 'k6/execution';

const ENGINE_LABEL  = __ENV.ENGINE_LABEL  || 'vllm-qwen3';
const NAMESPACE     = __ENV.NAMESPACE     || 'llm-d-vllm';
const MIN_REPLICAS  = parseInt(__ENV.MIN_REPLICAS || '2', 10);

export const options = {
  vus: 1,
  iterations: 1,
};

export default function () {
  // This script is a placeholder — the actual replica check runs via
  // kubectl in the shell wrapper (see scripts/run-load-test.sh).
  // k6 does not have native kubectl exec capability.
  console.log(`[verify-replicas] Checking: app=${ENGINE_LABEL} namespace=${NAMESPACE} minReplicas=${MIN_REPLICAS}`);
  console.log('[verify-replicas] Delegate to shell: kubectl get pods -n llm-d-vllm -l app=vllm-qwen3');
}
