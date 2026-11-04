#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kedacore https://kedacore.github.io/charts
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

kubectl apply -f monitoring/namespaces.yaml

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/kube-prometheus-stack/values.yaml

helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  -n monitoring -f monitoring/dcgm-exporter/values.yaml

helm upgrade --install keda kedacore/keda -n keda --create-namespace -f monitoring/keda/values.yaml
