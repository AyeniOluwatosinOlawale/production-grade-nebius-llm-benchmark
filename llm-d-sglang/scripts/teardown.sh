#!/usr/bin/env bash
# teardown.sh — Remove all nebius-llm-d-sglang resources from the cluster.
#
# By default, this removes application resources only (sglang, litellm, keda scaledobject,
# llmd CRDs). Pass --full to also uninstall the monitoring Helm releases.
#
# IMPORTANT: This does NOT delete the Nebius node pool. Remove that via the Nebius console
# or Terraform to stop GPU billing.
#
# Usage:
#   ./scripts/teardown.sh               # app resources only
#   ./scripts/teardown.sh --full        # app + monitoring Helm releases
#   DRY_RUN=true ./scripts/teardown.sh  # preview only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FULL_TEARDOWN=false
DRY_RUN="${DRY_RUN:-false}"

for arg in "$@"; do
  case "$arg" in
    --full) FULL_TEARDOWN=true ;;
    --dry-run) DRY_RUN=true ;;
  esac
done

KUBECTL="kubectl"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "==> DRY RUN MODE — commands will be printed but not executed"
  KUBECTL="echo kubectl"
fi

echo "============================================================"
echo "  nebius-llm-d-sglang — Teardown"
echo "  Full teardown: ${FULL_TEARDOWN}"
echo "============================================================"
echo ""

# ── KEDA ScaledObject (remove first to stop autoscaling) ──────────
echo "==> Removing KEDA ScaledObject..."
${KUBECTL} delete scaledobject sglang-qwen3-scaledobject \
  --namespace llm-inference --ignore-not-found=true

# ── LiteLLM ───────────────────────────────────────────────────────
echo ""
echo "==> Removing LiteLLM..."
${KUBECTL} delete deployment litellm \
  --namespace llm-inference --ignore-not-found=true
${KUBECTL} delete service litellm \
  --namespace llm-inference --ignore-not-found=true
${KUBECTL} delete configmap litellm-config \
  --namespace llm-inference --ignore-not-found=true

# ── llm-d CRDs ────────────────────────────────────────────────────
echo ""
echo "==> Removing llm-d InferenceModel and InferencePool..."
${KUBECTL} delete inferencemodel qwen3-27b \
  --namespace llm-inference --ignore-not-found=true
${KUBECTL} delete inferencepool qwen3-pool \
  --namespace llm-inference --ignore-not-found=true

# ── SGLang ────────────────────────────────────────────────────────
echo ""
echo "==> Removing SGLang deployment..."
${KUBECTL} delete deployment sglang-qwen3 \
  --namespace llm-inference --ignore-not-found=true
${KUBECTL} delete service sglang-qwen3 \
  --namespace llm-inference --ignore-not-found=true

echo ""
echo "==> Removing SGLang PVC (this deletes the model cache)..."
read -r -p "    Delete sglang-model-cache PVC? [y/N] " confirm
if [[ "${confirm}" =~ ^[Yy]$ ]]; then
  ${KUBECTL} delete pvc sglang-model-cache \
    --namespace llm-inference --ignore-not-found=true
  echo "    PVC deleted."
else
  echo "    PVC retained — delete manually: kubectl delete pvc sglang-model-cache -n llm-inference"
fi

# ── Prometheus rules & ServiceMonitors ────────────────────────────
echo ""
echo "==> Removing Prometheus rules and ServiceMonitors..."
${KUBECTL} delete prometheusrule llm-recording-rules \
  --namespace monitoring --ignore-not-found=true
${KUBECTL} delete servicemonitor sglang-metrics \
  --namespace monitoring --ignore-not-found=true
${KUBECTL} delete servicemonitor dcgm-exporter \
  --namespace monitoring --ignore-not-found=true

# ── Full teardown: Helm releases ─────────────────────────────────
if [[ "${FULL_TEARDOWN}" == "true" ]]; then
  echo ""
  echo "==> Full teardown — removing Helm releases..."

  for release in kube-prometheus-stack dcgm-exporter; do
    echo "    Uninstalling ${release}..."
    helm uninstall "${release}" --namespace monitoring --ignore-not-found 2>/dev/null || \
      echo "    (${release} not found — skipping)"
  done

  echo "    Uninstalling keda..."
  helm uninstall keda --namespace keda --ignore-not-found 2>/dev/null || \
    echo "    (keda not found — skipping)"

  echo "    Uninstalling llm-d..."
  helm uninstall llm-d --namespace llm-d-system --ignore-not-found 2>/dev/null || \
    echo "    (llm-d not found — skipping)"

  echo ""
  echo "==> Removing namespaces..."
  for ns in llm-inference monitoring llm-d-system keda; do
    ${KUBECTL} delete namespace "${ns}" --ignore-not-found=true
  done
fi

echo ""
echo "============================================================"
echo "  Teardown complete."
if [[ "${FULL_TEARDOWN}" != "true" ]]; then
  echo "  Monitoring stack retained. Run with --full to remove it."
fi
echo ""
echo "  REMINDER: Stop the Nebius H100 node pool to end GPU billing:"
echo "    nebius compute node-group delete gpu-h100-preemptible"
echo "============================================================"
