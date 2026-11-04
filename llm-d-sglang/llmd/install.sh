#!/usr/bin/env bash
# install.sh — Install llm-d into the cluster
# llm-d provides a Kubernetes-native inference scheduler that sits between
# the LiteLLM proxy and the SGLang engine pods.
#
# Docs: https://github.com/llm-d/llm-d
set -euo pipefail

LLMD_VERSION="${LLMD_VERSION:-v0.0.5}"
LLMD_NAMESPACE="llm-d-system"

echo "==> Installing llm-d ${LLMD_VERSION} into namespace ${LLMD_NAMESPACE}"

# 1. Add and update the llm-d Helm repository
helm repo add llm-d https://llm-d.github.io/llm-d-deployer/charts || true
helm repo update

# 2. Create namespace
kubectl create namespace "${LLMD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 3. Install / upgrade llm-d
helm upgrade --install llm-d llm-d/llm-d \
  --namespace "${LLMD_NAMESPACE}" \
  --version "${LLMD_VERSION}" \
  --set controller.replicaCount=2 \
  --set epp.replicaCount=2 \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.serviceMonitor.additionalLabels.release=kube-prometheus-stack \
  --wait \
  --timeout 5m

echo "==> llm-d installed successfully"

# 4. Wait for the EPP (Endpoint Picker Policy) pod to be ready
echo "==> Waiting for llm-d EPP pods to become ready..."
kubectl rollout status deployment/llm-d-epp \
  --namespace "${LLMD_NAMESPACE}" \
  --timeout=120s

echo "==> llm-d is ready"

# 5. Apply InferencePool and InferenceModel CRDs
echo "==> Applying InferencePool and InferenceModel..."
kubectl apply -f "$(dirname "$0")/inferencepool.yaml"
kubectl apply -f "$(dirname "$0")/inferencemodel.yaml"

echo "==> llm-d setup complete"
