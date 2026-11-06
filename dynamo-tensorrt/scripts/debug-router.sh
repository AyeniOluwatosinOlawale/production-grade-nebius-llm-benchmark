#!/bin/bash
# Debug Dynamo router model discovery.
# Run this after workers are deployed to diagnose why /v1/models is empty.
set -euo pipefail

NAMESPACE="llm-inference"
ETCD_POD=$(kubectl get pod -n "$NAMESPACE" -l app=etcd -o jsonpath='{.items[0].metadata.name}')
ROUTER_POD=$(kubectl get pod -n "$NAMESPACE" -l app=dynamo-router -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
PREFILL_POD=$(kubectl get pod -n "$NAMESPACE" -l app=dynamo-tensorrt-prefill -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
DECODE_POD=$(kubectl get pod -n "$NAMESPACE" -l app=dynamo-tensorrt-decode -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

echo "========================================"
echo "  Dynamo-TensorRT Router Debug"
echo "========================================"
echo ""

echo "--- Pod Status ---"
kubectl get pods -n "$NAMESPACE"
echo ""

echo "--- etcd: ALL keys registered by workers ---"
kubectl exec -n "$NAMESPACE" "$ETCD_POD" -- etcdctl get "" --prefix --keys-only 2>/dev/null || echo "WARN: etcdctl failed"
echo ""

echo "--- etcd: Keys under dynamo-tensorrt namespace ---"
kubectl exec -n "$NAMESPACE" "$ETCD_POD" -- etcdctl get "dynamo-tensorrt" --prefix --keys-only 2>/dev/null || echo "(no keys under dynamo-tensorrt prefix)"
echo ""

echo "--- etcd: Keys under /dynamo-tensorrt namespace ---"
kubectl exec -n "$NAMESPACE" "$ETCD_POD" -- etcdctl get "/dynamo-tensorrt" --prefix --keys-only 2>/dev/null || echo "(no keys under /dynamo-tensorrt prefix)"
echo ""

echo "--- etcd: ALL key-value pairs (full dump) ---"
kubectl exec -n "$NAMESPACE" "$ETCD_POD" -- etcdctl get "" --prefix 2>/dev/null | head -100 || echo "WARN: etcdctl failed"
echo ""

echo "--- Router: /v1/models response ---"
if [ -n "$ROUTER_POD" ]; then
  kubectl exec -n "$NAMESPACE" "$ROUTER_POD" -- curl -s http://localhost:8080/v1/models 2>/dev/null || echo "WARN: curl inside router failed"
else
  echo "WARN: no router pod found"
fi
echo ""

echo "--- Router: /health response ---"
if [ -n "$ROUTER_POD" ]; then
  kubectl exec -n "$NAMESPACE" "$ROUTER_POD" -- curl -s http://localhost:8080/health 2>/dev/null || echo "(no /health endpoint)"
fi
echo ""

echo "--- Router logs (last 50 lines) ---"
if [ -n "$ROUTER_POD" ]; then
  kubectl logs -n "$NAMESPACE" "$ROUTER_POD" --tail=50 2>/dev/null || echo "WARN: no router logs"
fi
echo ""

echo "--- TensorRT Prefill worker logs (last 30 lines) ---"
if [ -n "$PREFILL_POD" ]; then
  kubectl logs -n "$NAMESPACE" "$PREFILL_POD" --tail=30 2>/dev/null || echo "WARN: no prefill logs"
fi
echo ""

echo "--- TensorRT Decode worker logs (last 30 lines) ---"
if [ -n "$DECODE_POD" ]; then
  kubectl logs -n "$NAMESPACE" "$DECODE_POD" --tail=30 2>/dev/null || echo "WARN: no decode logs"
fi
echo ""

echo "--- NATS: connection check from router ---"
if [ -n "$ROUTER_POD" ]; then
  kubectl exec -n "$NAMESPACE" "$ROUTER_POD" -- python3 -c \
    "import socket; s=socket.create_connection(('nats.llm-inference',4222),timeout=3); print('NATS OK'); s.close()" 2>/dev/null || echo "WARN: NATS not reachable from router"
fi
echo ""

echo "--- etcd: connection check from router ---"
if [ -n "$ROUTER_POD" ]; then
  kubectl exec -n "$NAMESPACE" "$ROUTER_POD" -- python3 -c \
    "import socket; s=socket.create_connection(('etcd.llm-inference',2379),timeout=3); print('etcd OK'); s.close()" 2>/dev/null || echo "WARN: etcd not reachable from router"
fi
echo ""

echo "========================================"
echo "  Debug complete."
echo "  If /v1/models is empty:"
echo "  1. Check etcd keys above — do workers register anything?"
echo "  2. Check router logs — does it log 'discovered model' or errors?"
echo "  3. Check NATS/etcd connectivity from router pod"
echo "========================================"
