#!/bin/bash
set -euo pipefail
echo "=== nebius-dynamo-sglang -- Install Dependencies ==="

kubectl apply -f monitoring/namespaces.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --values monitoring/kube-prometheus-stack/values.yaml --wait --timeout 10m

helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  -n monitoring --values monitoring/dcgm-exporter/values.yaml --wait --timeout 5m

helm upgrade --install keda kedacore/keda \
  -n keda --create-namespace \
  --values monitoring/keda/values.yaml --wait --timeout 5m

kubectl apply -f monitoring/servicemonitors/engine-servicemonitor.yaml
kubectl apply -f monitoring/servicemonitors/dcgm-servicemonitor.yaml
kubectl apply -f monitoring/prometheus-rules/llm-recording-rules.yaml

kubectl create configmap gpu-overview-dashboard \
  --from-file=gpu-overview.json=monitoring/dashboards/gpu-overview.json \
  -n monitoring --dry-run=client -o yaml | \
  kubectl label -f - grafana_dashboard=1 --local -o yaml | kubectl apply -f -

kubectl create configmap llm-throughput-dashboard \
  --from-file=throughput.json=monitoring/dashboards/throughput.json \
  -n monitoring --dry-run=client -o yaml | \
  kubectl label -f - grafana_dashboard=1 --local -o yaml | kubectl apply -f -

echo "=== Done. Next: ./scripts/deploy.sh ==="
