#!/usr/bin/env bash
# deploy.sh — Deploy the full nebius-llm-d-sglang stack to Kubernetes.
#
# Deployment order:
#   1. Namespaces
#   2. Monitoring stack (Prometheus + Grafana + DCGM + KEDA)
#   3. llm-d (scheduler)
#   4. SGLang engine (PVC → Deployment → Service)
#   5. LiteLLM proxy
#   6. KEDA ScaledObject
#   7. Prometheus recording rules + ServiceMonitors
#
# Usage:
#   ./scripts/deploy.sh
#   DRY_RUN=true ./scripts/deploy.sh        # kubectl apply --dry-run=client
#   SKIP_MONITORING=true ./scripts/deploy.sh # skip Helm stack installs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DRY_RUN="${DRY_RUN:-false}"
SKIP_MONITORING="${SKIP_MONITORING:-false}"
KUBE_APPLY="kubectl apply"
if [[ "${DRY_RUN}" == "true" ]]; then
  KUBE_APPLY="kubectl apply --dry-run=client"
  echo "==> DRY RUN MODE — no resources will be created"
fi

echo "============================================================"
echo "  nebius-llm-d-sglang — Full Stack Deployment"
echo "============================================================"
echo "  Repo root:  ${REPO_ROOT}"
echo "  Cluster:    $(kubectl config current-context)"
echo ""

# ── 1. Namespaces ─────────────────────────────────────────────────
echo "==> [1/7] Creating namespaces..."
${KUBE_APPLY} -f "${REPO_ROOT}/monitoring/namespaces.yaml"

# ── 2. Monitoring stack ───────────────────────────────────────────
if [[ "${SKIP_MONITORING}" != "true" ]]; then
  echo ""
  echo "==> [2/7] Installing monitoring stack..."

  echo "    Installing kube-prometheus-stack..."
  helm upgrade --install kube-prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --values "${REPO_ROOT}/monitoring/kube-prometheus-stack/values.yaml" \
    --wait \
    --timeout 10m

  echo "    Installing DCGM Exporter..."
  helm upgrade --install dcgm-exporter \
    gpu-helm-charts/dcgm-exporter \
    --namespace monitoring \
    --values "${REPO_ROOT}/monitoring/dcgm-exporter/values.yaml" \
    --wait \
    --timeout 5m

  echo "    Installing KEDA..."
  helm upgrade --install keda \
    kedacore/keda \
    --namespace keda \
    --create-namespace \
    --values "${REPO_ROOT}/monitoring/keda/values.yaml" \
    --wait \
    --timeout 5m
else
  echo ""
  echo "==> [2/7] SKIP_MONITORING=true — skipping Helm stack installs"
fi

# ── 3. llm-d ─────────────────────────────────────────────────────
echo ""
echo "==> [3/7] Installing llm-d..."
bash "${REPO_ROOT}/llmd/install.sh"

# ── 4. SGLang engine ──────────────────────────────────────────────
echo ""
echo "==> [4/7] Deploying SGLang engine..."

echo "    Applying PVC..."
${KUBE_APPLY} -f "${REPO_ROOT}/sglang/pvc.yaml"

echo "    Applying Deployment..."
${KUBE_APPLY} -f "${REPO_ROOT}/sglang/deployment.yaml"

echo "    Applying Service..."
${KUBE_APPLY} -f "${REPO_ROOT}/sglang/service.yaml"

if [[ "${DRY_RUN}" != "true" ]]; then
  echo "    Waiting for SGLang rollout (may take 5-10min for model download)..."
  kubectl rollout status deployment/sglang-qwen3 \
    --namespace llm-inference \
    --timeout=20m
fi

# ── 5. LiteLLM proxy ─────────────────────────────────────────────
echo ""
echo "==> [5/7] Deploying LiteLLM proxy..."
${KUBE_APPLY} -f "${REPO_ROOT}/litellm/configmap.yaml"
${KUBE_APPLY} -f "${REPO_ROOT}/litellm/deployment.yaml"
${KUBE_APPLY} -f "${REPO_ROOT}/litellm/service.yaml"

if [[ "${DRY_RUN}" != "true" ]]; then
  kubectl rollout status deployment/litellm \
    --namespace llm-inference \
    --timeout=5m
fi

# ── 6. KEDA ScaledObject ─────────────────────────────────────────
echo ""
echo "==> [6/7] Applying KEDA ScaledObject..."
${KUBE_APPLY} -f "${REPO_ROOT}/keda/scaledobject.yaml"

# ── 7. Prometheus rules & ServiceMonitors ────────────────────────
echo ""
echo "==> [7/7] Applying Prometheus rules and ServiceMonitors..."
${KUBE_APPLY} -f "${REPO_ROOT}/monitoring/prometheus-rules/llm-recording-rules.yaml"
${KUBE_APPLY} -f "${REPO_ROOT}/monitoring/servicemonitors/engine-servicemonitor.yaml"
${KUBE_APPLY} -f "${REPO_ROOT}/monitoring/servicemonitors/dcgm-servicemonitor.yaml"

# ── Status summary ────────────────────────────────────────────────
if [[ "${DRY_RUN}" != "true" ]]; then
  echo ""
  echo "============================================================"
  echo "  Deployment Complete — Stack Status"
  echo "============================================================"
  echo ""
  echo "  SGLang pods:"
  kubectl get pods -n llm-inference -l app=sglang-qwen3 \
    -o wide 2>/dev/null || true

  echo ""
  echo "  LiteLLM pods:"
  kubectl get pods -n llm-inference -l app=litellm \
    -o wide 2>/dev/null || true

  echo ""
  echo "  KEDA ScaledObject:"
  kubectl get scaledobject -n llm-inference 2>/dev/null || true

  echo ""
  echo "  Grafana (port-forward to access):"
  echo "    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
  echo ""
  echo "  LiteLLM (port-forward to test):"
  echo "    kubectl port-forward -n llm-inference svc/litellm 4000:4000"
  echo ""
  echo "  Run load tests:"
  echo "    ./scripts/run-load-test.sh smoke"
  echo "============================================================"
fi
