#!/usr/bin/env bash
# Install llm-d (Kubernetes Gateway API + llm-d operator + EPP)
# Docs: https://github.com/llm-d/llm-d
set -euo pipefail

echo "==> Installing Gateway API CRDs (standard channel)..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

echo "==> Installing llm-d operator via Helm..."
helm repo add llm-d https://llm-d.github.io/llm-d-helm || true
helm repo update

helm upgrade --install llm-d llm-d/llm-d \
  --namespace llm-d-system \
  --create-namespace \
  --set epp.image.tag=latest \
  --wait --timeout=5m

echo "==> Waiting for llm-d EPP to be ready..."
kubectl rollout status deployment/llm-d-epp -n llm-d-system --timeout=3m

echo "==> llm-d installed successfully."
kubectl get pods -n llm-d-system
