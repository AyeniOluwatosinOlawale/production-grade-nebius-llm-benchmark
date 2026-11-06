#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f tensorrt/pvc.yaml
kubectl apply -f dynamo/nats.yaml
kubectl apply -f dynamo/etcd.yaml
kubectl apply -f dynamo/pipeline-config.yaml
kubectl apply -f dynamo/prefill.yaml
kubectl apply -f dynamo/decode.yaml
kubectl apply -f dynamo/router.yaml
kubectl apply -f dynamo/service.yaml
kubectl apply -f tensorrt/service.yaml
kubectl apply -f litellm/secret.yaml
kubectl apply -f litellm/configmap.yaml
kubectl apply -f litellm/deployment.yaml
kubectl apply -f litellm/service.yaml
kubectl apply -f monitoring/servicemonitors/engine-servicemonitor.yaml
kubectl apply -f monitoring/servicemonitors/dcgm-servicemonitor.yaml
kubectl apply -f monitoring/prometheus-rules/llm-recording-rules.yaml
kubectl apply -f keda/scaledobject-prefill.yaml
kubectl apply -f keda/scaledobject-decode.yaml

echo "Waiting for decode pods ready..."
kubectl rollout status deployment/dynamo-tensorrt-decode -n llm-inference --timeout=600s
