#!/usr/bin/env bash
set -euo pipefail

STACKS=(llm-d-vllm llm-d-sglang llm-d-tensorrt dynamo-vllm dynamo-sglang dynamo-tensorrt)

for stack in "${STACKS[@]}"; do
  echo ""
  echo "============================================"
  echo "  Deploying: $stack"
  echo "============================================"
  cd "$(dirname "$0")/$stack"
  bash scripts/install-deps.sh
  bash scripts/deploy.sh
  bash scripts/run-load-test.sh
  bash scripts/teardown.sh
  cd ..
done

echo ""
echo "All 6 stacks complete."
