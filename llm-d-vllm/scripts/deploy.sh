#!/bin/bash
# Deploy all LLM inference manifests: vLLM PVC, vLLM Deployment, llm-d CRDs, LiteLLM, KEDA
set -euo pipefail

echo "================================================"
echo "  nebius-llm-d-vllm — Deploy"
echo "================================================"

NAMESPACE="llm-inference"

echo ""
echo "==> Applying vLLM PVC..."
kubectl apply -f vllm/pvc.yaml

echo ""
echo "==> Applying vLLM Deployment and Service..."
kubectl apply -f vllm/deployment.yaml
kubectl apply -f vllm/service.yaml

echo ""
echo "==> Applying llm-d InferencePool and InferenceModel..."
kubectl apply -f llmd/inferencepool.yaml
kubectl apply -f llmd/inferencemodel.yaml

echo ""
echo "==> Applying LiteLLM..."
kubectl apply -f litellm/configmap.yaml
kubectl apply -f litellm/deployment.yaml
kubectl apply -f litellm/service.yaml

echo ""
echo "==> Applying KEDA ScaledObject..."
kubectl apply -f keda/scaledobject.yaml

echo ""
echo "==> Waiting for vLLM pods to be ready (this takes 5–10 min for model load)..."
kubectl rollout status deployment/vllm-qwen3 -n "$NAMESPACE" --timeout=15m || {
  echo "WARN: Rollout timed out — check pod logs: kubectl logs -n $NAMESPACE -l app=vllm-qwen3"
}

echo ""
echo "==> Waiting for LiteLLM to be ready..."
kubectl rollout status deployment/litellm -n "$NAMESPACE" --timeout=5m

echo ""
LB_IP=$(kubectl get svc litellm -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
echo "================================================"
echo "  Deploy complete!"
echo "  LiteLLM endpoint: http://${LB_IP}:4000"
echo "  Test: curl http://${LB_IP}:4000/v1/models"
echo "  Next: BASE_URL=http://${LB_IP}:4000 ./scripts/run-load-test.sh"
echo "================================================"
