#!/bin/bash
# Install all Helm dependencies: KEDA, Prometheus, DCGM Exporter, Gateway API CRDs, llm-d operator
set -euo pipefail

echo "================================================"
echo "  nebius-llm-d-vllm — Dependency Installer"
echo "================================================"

# --- Namespace setup ---
echo ""
echo "==> Creating namespaces..."
kubectl apply -f monitoring/namespaces.yaml

# --- Gateway API CRDs ---
echo ""
echo "==> Installing Gateway API CRDs..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=60s

# --- Helm repos ---
echo ""
echo "==> Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts 2>/dev/null || true
helm repo add llm-d https://llm-d.github.io/llm-d 2>/dev/null || true
helm repo update

# --- kube-prometheus-stack ---
echo ""
echo "==> Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring/kube-prometheus-stack/values.yaml \
  --wait --timeout 10m

# --- DCGM Exporter ---
echo ""
echo "==> Installing DCGM Exporter..."
helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace monitoring \
  --values monitoring/dcgm-exporter/values.yaml \
  --wait --timeout 5m

# --- KEDA ---
echo ""
echo "==> Installing KEDA..."
helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --values monitoring/keda/values.yaml \
  --wait --timeout 5m

# --- llm-d operator ---
echo ""
echo "==> Installing llm-d operator..."
bash llmd/install.sh

# --- Prometheus recording rules + ServiceMonitors ---
echo ""
echo "==> Applying Prometheus rules and ServiceMonitors..."
kubectl apply -f monitoring/servicemonitors/engine-servicemonitor.yaml
kubectl apply -f monitoring/servicemonitors/dcgm-servicemonitor.yaml
kubectl apply -f monitoring/prometheus-rules/llm-recording-rules.yaml

# --- Grafana dashboards ---
echo ""
echo "==> Loading Grafana dashboards..."
kubectl create configmap gpu-overview-dashboard \
  --from-file=gpu-overview.json=monitoring/dashboards/gpu-overview.json \
  --namespace monitoring \
  --dry-run=client -o yaml | \
  kubectl label -f - grafana_dashboard=1 --local -o yaml | \
  kubectl apply -f -

kubectl create configmap llm-throughput-dashboard \
  --from-file=throughput.json=monitoring/dashboards/throughput.json \
  --namespace monitoring \
  --dry-run=client -o yaml | \
  kubectl label -f - grafana_dashboard=1 --local -o yaml | \
  kubectl apply -f -

echo ""
echo "================================================"
echo "  Dependencies installed successfully!"
echo "  Next: ./scripts/deploy.sh"
echo "================================================"
