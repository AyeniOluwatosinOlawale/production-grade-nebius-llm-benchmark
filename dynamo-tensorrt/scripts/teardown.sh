#!/usr/bin/env bash
set -euo pipefail

kubectl delete -f keda/ --ignore-not-found
kubectl delete -f dynamo/ --ignore-not-found
kubectl delete -f tensorrt/ --ignore-not-found
kubectl delete -f litellm/ --ignore-not-found
helm uninstall dcgm-exporter -n monitoring || true
helm uninstall kube-prometheus-stack -n monitoring || true
helm uninstall keda -n keda || true
