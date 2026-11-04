#!/usr/bin/env bash
# Deploy nebius-llm-d-tensorrt stack to Kubernetes
# Prerequisites: install-deps.sh must have been run first
set -euo pipefail

NAMESPACE="llm-inference"

echo "==> Creating namespace ${NAMESPACE} (if not exists)..."
kubectl apply -f monitoring/namespaces.yaml

echo "==> Deploying TensorRT-LLM engine..."
kubectl apply -f tensorrt/pvc.yaml
kubectl apply -f tensorrt/deployment.yaml
kubectl apply -f tensorrt/service.yaml

echo "==> Deploying LiteLLM proxy..."
kubectl apply -f litellm/configmap.yaml
kubectl apply -f litellm/deployment.yaml
kubectl apply -f litellm/service.yaml

echo "==> Applying llm-d InferencePool and InferenceModel..."
kubectl apply -f llmd/inferencepool.yaml
kubectl apply -f llmd/inferencemodel.yaml

echo "==> Applying KEDA ScaledObject..."
kubectl apply -f keda/scaledobject.yaml

echo "==> Applying ServiceMonitors and PrometheusRules..."
kubectl apply -f monitoring/servicemonitors/engine-servicemonitor.yaml
kubectl apply -f monitoring/servicemonitors/dcgm-servicemonitor.yaml
kubectl apply -f monitoring/prometheus-rules/llm-recording-rules.yaml

echo ""
echo "==> Waiting for TensorRT-LLM deployment rollout (this can take 10+ min for model download)..."
kubectl rollout status deployment/tensorrt-qwen3 -n "${NAMESPACE}" --timeout=20m

echo "==> Waiting for LiteLLM deployment rollout..."
kubectl rollout status deployment/litellm -n "${NAMESPACE}" --timeout=3m

echo ""
echo "Stack deployed successfully."
echo ""
echo "Get the LiteLLM LoadBalancer IP:"
kubectl get svc litellm -n "${NAMESPACE}"
echo ""
echo "Next: ./scripts/run-load-test.sh"
