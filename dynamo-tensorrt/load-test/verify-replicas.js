import http from 'k6/http';
import { check } from 'k6';

// Reads the decode deployment replica status via the Kubernetes API.
// Requires the k6 runner to have a ServiceAccount with read access to deployments,
// and KUBE_API_URL / KUBE_TOKEN set as k6 environment variables.
//
// Usage:
//   k6 run \
//     -e KUBE_API_URL=https://<cluster-api> \
//     -e KUBE_TOKEN=$(kubectl create token k6-reader -n llm-inference) \
//     load-test/verify-replicas.js

const KUBE_API_URL = __ENV.KUBE_API_URL || 'https://kubernetes.default.svc';
const KUBE_TOKEN   = __ENV.KUBE_TOKEN   || '';
const NAMESPACE    = 'llm-inference';
const DEPLOYMENT   = 'dynamo-tensorrt-decode';
const MIN_REPLICAS = 2;

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    // Custom check that decode pods are ready — will cause non-zero exit if fails
    checks: ['rate==1'],
  },
};

export default function () {
  const url = `${KUBE_API_URL}/apis/apps/v1/namespaces/${NAMESPACE}/deployments/${DEPLOYMENT}`;

  const params = {
    headers: {
      Authorization: `Bearer ${KUBE_TOKEN}`,
      Accept: 'application/json',
    },
    // Skip TLS verification for in-cluster calls where cert is from the cluster CA
    insecureSkipTLSVerify: true,
  };

  const res = http.get(url, params);

  const ok = check(res, {
    'kubernetes API responded 200': (r) => r.status === 200,
  });

  if (!ok) {
    console.error(`Failed to reach Kubernetes API: HTTP ${res.status}`);
    return;
  }

  let deployment;
  try {
    deployment = JSON.parse(res.body);
  } catch (e) {
    console.error('Failed to parse Kubernetes API response:', e);
    return;
  }

  const readyReplicas = (deployment.status && deployment.status.readyReplicas) || 0;

  console.log(`Deployment ${DEPLOYMENT}: readyReplicas=${readyReplicas} (minimum required: ${MIN_REPLICAS})`);

  check(readyReplicas, {
    [`decode deployment has >= ${MIN_REPLICAS} ready replicas`]: (n) => n >= MIN_REPLICAS,
  });
}
