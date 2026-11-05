#!/bin/bash
set -euo pipefail
echo "=== nebius-dynamo-vllm — Install Dependencies ==="

# Create dynamo-vllm namespace (shared monitoring stack already installed by llm-d-vllm)
kubectl apply -f monitoring/namespaces.yaml

# Skip kube-prometheus-stack, dcgm-exporter, keda if already installed
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
helm repo update

if ! helm status kube-prometheus-stack -n monitoring &>/dev/null; then
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace \
    --values monitoring/kube-prometheus-stack/values.yaml --wait --timeout 10m
else
  echo "==> kube-prometheus-stack already installed, skipping."
fi

if ! helm status dcgm-exporter -n monitoring &>/dev/null; then
  helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
    -n monitoring --values monitoring/dcgm-exporter/values.yaml --wait --timeout 5m
else
  echo "==> dcgm-exporter already installed, skipping."
fi

if ! helm status keda -n keda &>/dev/null; then
  helm upgrade --install keda kedacore/keda \
    -n keda --create-namespace \
    --values monitoring/keda/values.yaml --wait --timeout 5m
else
  echo "==> keda already installed, skipping."
fi

# Stack-specific: engine ServiceMonitor, recording rules, dashboards
kubectl apply -f monitoring/servicemonitors/engine-servicemonitor.yaml
kubectl apply -f monitoring/servicemonitors/dcgm-servicemonitor.yaml
kubectl apply -f monitoring/prometheus-rules/llm-recording-rules.yaml

kubectl create configmap dynamo-vllm-gpu-dashboard \
  --from-file=gpu-overview.json=monitoring/dashboards/gpu-overview.json \
  -n monitoring --dry-run=client -o yaml | \
  kubectl label -f - grafana_dashboard=1 --local -o yaml | kubectl apply -f -

kubectl create configmap dynamo-vllm-throughput-dashboard \
  --from-file=throughput.json=monitoring/dashboards/throughput.json \
  -n monitoring --dry-run=client -o yaml | \
  kubectl label -f - grafana_dashboard=1 --local -o yaml | kubectl apply -f -

echo "=== Done. Next: ./scripts/deploy.sh ==="
