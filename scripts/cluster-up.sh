#!/usr/bin/env bash
# Create (or update) the local kind cluster and deploy OpsPilot's services.
#   bash scripts/cluster-up.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=opspilot
CTX="kind-$CLUSTER"          # always target this context, never your work clusters
K="kubectl --context $CTX"

for bin in docker kind kubectl; do
  command -v "$bin" >/dev/null || { echo "Missing: $bin"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "Docker isn't running"; exit 1; }

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "==> Creating kind cluster '$CLUSTER'"
  kind create cluster --config deploy/kind/cluster.yaml --wait 120s
fi

echo "==> Building images"
for s in inventory orders; do
  docker build -q -t "opspilot/$s:dev" "services/$s"
  kind load docker-image "opspilot/$s:dev" --name "$CLUSTER"
done

echo "==> Applying manifests"
$K apply -f deploy/k8s/
# Same :dev tag every time, so force pods to pick up the freshly loaded image
$K -n opspilot rollout restart deployment/inventory deployment/orders
for d in inventory orders; do
  $K -n opspilot rollout status "deployment/$d" --timeout=120s
done

echo "==> Smoke test"
for i in $(seq 1 20); do
  curl -fsS http://127.0.0.1:9001/healthz >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://127.0.0.1:9001/low-stock; echo
curl -fsS -X POST http://127.0.0.1:9002/orders -H "Content-Type: application/json" \
  -d '{"sku":"paracetamol-500","qty":1}'; echo

$K -n opspilot get pods -o wide
echo
echo "Inventory: http://127.0.0.1:9001/docs"
echo "Orders:    http://127.0.0.1:9002/docs"
