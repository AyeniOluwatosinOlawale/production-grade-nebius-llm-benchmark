#!/usr/bin/env bash
# install-deps.sh — Install all dependencies for nebius-llm-d-sglang
# Run once per machine / CI runner before deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================================"
echo "  nebius-llm-d-sglang — Dependency Installer"
echo "============================================================"

# ── Helpers ──────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }
require() {
  if ! command_exists "$1"; then
    echo "ERROR: '$1' is required but not installed." >&2
    echo "       $2" >&2
    exit 1
  fi
  echo "  [ok] $1 ($(command -v "$1"))"
}

# ── Check required tools ──────────────────────────────────────────
echo ""
echo "==> Checking required tools..."
require kubectl  "Install from https://kubernetes.io/docs/tasks/tools/"
require helm     "Install from https://helm.sh/docs/intro/install/"
require k6       "Install from https://k6.io/docs/getting-started/installation/"
require node     "Install from https://nodejs.org/"
require jq       "Install via: brew install jq  or  apt install jq"

echo ""
echo "==> Checking optional tools..."
for tool in nebius yq; do
  if command_exists "$tool"; then
    echo "  [ok] $tool"
  else
    echo "  [--] $tool (optional — not installed)"
  fi
done

# ── Helm repos ────────────────────────────────────────────────────
echo ""
echo "==> Adding Helm repositories..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts 2>/dev/null || true
helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
helm repo add llm-d https://llm-d.github.io/llm-d-deployer/charts 2>/dev/null || true

helm repo update
echo "  [ok] Helm repos updated"

# ── k6 version check ─────────────────────────────────────────────
echo ""
echo "==> k6 version:"
k6 version

# ── Node.js deps ──────────────────────────────────────────────────
# verify-replicas.js uses only built-in Node modules (http, https) — no npm needed

echo ""
echo "==> Validating k6 load test scripts..."
k6 inspect "${REPO_ROOT}/load-test/smoke-test.js"     && echo "  [ok] smoke-test.js"
k6 inspect "${REPO_ROOT}/load-test/load-10k-ramp.js"  && echo "  [ok] load-10k-ramp.js"

echo ""
echo "============================================================"
echo "  All dependencies are installed and ready."
echo "  Next: ./scripts/deploy.sh"
echo "============================================================"
