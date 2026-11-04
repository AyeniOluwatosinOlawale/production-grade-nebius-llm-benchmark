const ENGINE_LABEL = __ENV.ENGINE_LABEL || 'sglang-decode';
const MIN_REPLICAS = parseInt(__ENV.MIN_REPLICAS || '2', 10);
export const options = { vus: 1, iterations: 1 };
export default function () {
  console.log(`[verify-replicas] app=${ENGINE_LABEL} minReplicas=${MIN_REPLICAS}`);
  console.log('[verify-replicas] Run: kubectl get pods -n llm-inference -l app=sglang-decode --field-selector=status.phase=Running');
}
