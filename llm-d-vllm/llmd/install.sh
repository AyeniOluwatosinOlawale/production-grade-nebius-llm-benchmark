#!/bin/bash
# Install llm-d operator and Gateway API CRDs
set -euo pipefail

echo "==> Installing Gateway API CRDs (v1.1.0 standard channel)..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

echo "==> Waiting for Gateway API CRDs to be established..."
kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=60s
kubectl wait --for=condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=60s

echo "==> Adding llm-d Helm repository..."
helm repo add llm-d https://llm-d.github.io/llm-d || true
helm repo update

echo "==> Installing llm-d inference scheduler operator..."
helm upgrade --install llm-d-inference-scheduler llm-d/llm-d-inference-scheduler \
  --namespace llm-d-system \
  --create-namespace \
  --wait \
  --timeout 5m \
  --set replicaCount=1 \
  --set tolerations[0].key=nvidia.com/gpu \
  --set tolerations[0].operator=Exists \
  --set tolerations[0].effect=NoSchedule \
  --set tolerations[1].key=cloud.nebius.ai/preemptible \
  --set tolerations[1].operator=Exists \
  --set tolerations[1].effect=NoSchedule

echo "==> Waiting for llm-d InferencePool CRD..."
kubectl wait --for=condition=Established crd/inferencepools.inference.networking.x-k8s.io --timeout=120s || \
  echo "WARN: InferencePool CRD not found — verify llm-d chart name against current release"

echo "==> llm-d operator installed successfully."
kubectl get pods -n llm-d-system
