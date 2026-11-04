#!/bin/bash
set -euo pipefail
echo "==> Tearing down nebius-dynamo-sglang..."
kubectl delete -f keda/scaledobject-decode.yaml --ignore-not-found
kubectl delete -f keda/scaledobject-prefill.yaml --ignore-not-found
kubectl delete -f litellm/service.yaml --ignore-not-found
kubectl delete -f litellm/deployment.yaml --ignore-not-found
kubectl delete -f litellm/configmap.yaml --ignore-not-found
kubectl delete -f dynamo/router.yaml --ignore-not-found
kubectl delete -f dynamo/decode.yaml --ignore-not-found
kubectl delete -f dynamo/prefill.yaml --ignore-not-found
kubectl delete -f dynamo/pipeline-config.yaml --ignore-not-found
kubectl delete -f dynamo/etcd.yaml --ignore-not-found
kubectl delete -f dynamo/nats.yaml --ignore-not-found
read -rp "Delete SGLang model cache PVC? [y/N] " C
[[ "$C" =~ ^[Yy]$ ]] && kubectl delete -f sglang/pvc.yaml --ignore-not-found || echo "PVC preserved."
echo "==> Done."
