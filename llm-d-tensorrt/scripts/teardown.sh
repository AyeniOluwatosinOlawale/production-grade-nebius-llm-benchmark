#!/usr/bin/env bash
# Tear down the nebius-llm-d-tensorrt stack
# Does NOT remove monitoring dependencies (prometheus, KEDA, DCGM) — only engine resources
set -euo pipefail

NAMESPACE="llm-inference"

echo "==> WARNING: This will delete all resources in namespace ${NAMESPACE}"
read -r -p "Are you sure? [y/N] " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo "==> Removing KEDA ScaledObject..."
kubectl delete -f keda/scaledobject.yaml --ignore-not-found

echo "==> Removing ServiceMonitors and PrometheusRules..."
kubectl delete -f monitoring/servicemonitors/engine-servicemonitor.yaml --ignore-not-found
kubectl delete -f monitoring/prometheus-rules/llm-recording-rules.yaml --ignore-not-found

echo "==> Removing llm-d InferenceModel and InferencePool..."
kubectl delete -f llmd/inferencemodel.yaml --ignore-not-found
kubectl delete -f llmd/inferencepool.yaml --ignore-not-found

echo "==> Removing LiteLLM..."
kubectl delete -f litellm/service.yaml --ignore-not-found
kubectl delete -f litellm/deployment.yaml --ignore-not-found
kubectl delete -f litellm/configmap.yaml --ignore-not-found

echo "==> Removing TensorRT-LLM engine..."
kubectl delete -f tensorrt/service.yaml --ignore-not-found
kubectl delete -f tensorrt/deployment.yaml --ignore-not-found

echo ""
echo "NOTE: PVC tensorrt-model-cache is preserved to avoid re-downloading the model."
echo "To delete it: kubectl delete pvc tensorrt-model-cache -n ${NAMESPACE}"
echo ""
echo "Teardown complete."
