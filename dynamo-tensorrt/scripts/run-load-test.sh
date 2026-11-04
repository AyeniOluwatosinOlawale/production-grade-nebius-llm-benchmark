#!/usr/bin/env bash
set -euo pipefail

LITELLM_IP=$(kubectl get svc litellm-svc -n llm-inference -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

k6 run -e BASE_URL=http://${LITELLM_IP}:4000 load-test/smoke-test.js
k6 run -e BASE_URL=http://${LITELLM_IP}:4000 load-test/load-10k-ramp.js
