#!/bin/bash
# Install Gateway API CRDs and inference extension CRDs for llm-d stacks.
# We route LiteLLM directly to the vLLM Service (no EPP/gateway needed for benchmarking).
set -euo pipefail

echo "==> Installing Gateway API CRDs (v1.1.0)..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

echo "==> Waiting for Gateway API CRDs..."
kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=60s
kubectl wait --for=condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=60s

echo "==> Installing inference extension CRDs (InferencePool, InferenceModel)..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v0.5.0/manifests.yaml || \
  echo "WARN: inference extension CRDs may already be installed or URL changed — continuing"

echo "==> llm-d CRD setup complete."
echo "    Routing: LiteLLM -> vllm-qwen3 Service -> vLLM pods (KEDA autoscaling)"
