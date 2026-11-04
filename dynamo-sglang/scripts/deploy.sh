#!/bin/bash
set -euo pipefail
NAMESPACE="llm-inference"
echo "=== nebius-dynamo-sglang -- Deploy ==="

kubectl apply -f sglang/pvc.yaml
kubectl apply -f dynamo/nats.yaml
kubectl apply -f dynamo/etcd.yaml
kubectl apply -f dynamo/pipeline-config.yaml

kubectl rollout status deployment/nats -n "$NAMESPACE" --timeout=2m
kubectl rollout status deployment/etcd -n "$NAMESPACE" --timeout=2m

kubectl apply -f dynamo/prefill.yaml
kubectl apply -f dynamo/decode.yaml
kubectl apply -f dynamo/router.yaml
kubectl apply -f litellm/configmap.yaml
kubectl apply -f litellm/deployment.yaml
kubectl apply -f litellm/service.yaml
kubectl apply -f keda/scaledobject-prefill.yaml
kubectl apply -f keda/scaledobject-decode.yaml

echo "==> Waiting for SGLang workers (5-10 min)..."
kubectl rollout status deployment/sglang-prefill -n "$NAMESPACE" --timeout=15m || echo "WARN: check logs"
kubectl rollout status deployment/sglang-decode -n "$NAMESPACE" --timeout=15m || echo "WARN: check logs"
kubectl rollout status deployment/litellm -n "$NAMESPACE" --timeout=5m

LB_IP=$(kubectl get svc litellm -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
echo "=== Deploy complete! LiteLLM: http://${LB_IP}:4000 ==="
