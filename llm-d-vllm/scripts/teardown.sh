#!/bin/bash
# Remove all LLM inference resources (keeps monitoring stack)
set -euo pipefail

NAMESPACE="llm-inference"

echo "==> Tearing down nebius-llm-d-vllm inference stack..."
echo "    (Monitoring stack in 'monitoring' namespace is preserved)"
echo ""

kubectl delete -f keda/scaledobject.yaml --ignore-not-found
kubectl delete -f litellm/service.yaml --ignore-not-found
kubectl delete -f litellm/deployment.yaml --ignore-not-found
kubectl delete -f litellm/configmap.yaml --ignore-not-found
kubectl delete -f llmd/inferencemodel.yaml --ignore-not-found
kubectl delete -f llmd/inferencepool.yaml --ignore-not-found
kubectl delete -f vllm/deployment.yaml --ignore-not-found
kubectl delete -f vllm/service.yaml --ignore-not-found

echo ""
read -rp "Delete model cache PVC (this deletes downloaded weights)? [y/N] " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  kubectl delete -f vllm/pvc.yaml --ignore-not-found
  echo "PVC deleted."
else
  echo "PVC preserved — model weights intact for next deploy."
fi

echo ""
echo "==> Teardown complete."
