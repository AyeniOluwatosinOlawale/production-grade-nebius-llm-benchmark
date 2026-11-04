#!/usr/bin/env bash
# Install all dependencies for nebius-llm-d-tensorrt
# Installs: kube-prometheus-stack, DCGM Exporter, KEDA, llm-d operator
set -euo pipefail

echo "==> Adding Helm repos..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo add kedacore https://kedacore.github.io/charts
helm repo add llm-d https://llm-d.github.io/llm-d-helm
helm repo update

echo "==> Applying namespaces..."
kubectl apply -f monitoring/namespaces.yaml

echo "==> Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f monitoring/kube-prometheus-stack/values.yaml \
  --wait --timeout=10m

echo "==> Installing DCGM Exporter..."
helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace monitoring \
  -f monitoring/dcgm-exporter/values.yaml \
  --wait --timeout=5m

echo "==> Installing KEDA..."
helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  -f monitoring/keda/values.yaml \
  --wait --timeout=5m

echo "==> Installing llm-d operator..."
bash llmd/install.sh

echo ""
echo "All dependencies installed successfully."
echo "Next: ./scripts/deploy.sh"
