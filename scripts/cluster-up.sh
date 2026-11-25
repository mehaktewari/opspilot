#!/usr/bin/env bash
# Create (or update) the local kind cluster and deploy OpsPilot's services with Helm.
#   bash scripts/cluster-up.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=opspilot
NS=opspilot
CTX="kind-$CLUSTER"          # always target this context, never your work clusters
K="kubectl --context $CTX"
CHART=deploy/helm/opspilot-app

for bin in docker kind kubectl helm; do
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

echo "==> Namespace with restricted Pod Security"
$K create namespace "$NS" --dry-run=client -o yaml | $K apply -f -
$K label --overwrite namespace "$NS" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  app.kubernetes.io/part-of=opspilot

# One-time migration: resources created by the old raw manifests (Day 4) aren't owned by Helm
$K -n "$NS" delete deployment,service \
  -l 'app.kubernetes.io/part-of=opspilot,app.kubernetes.io/managed-by!=Helm' --ignore-not-found

echo "==> helm upgrade --install"
helm lint "$CHART"
helm upgrade --install opspilot "$CHART" \
  --kube-context "$CTX" --namespace "$NS" \
  --wait --timeout 3m
# Same :dev tag every time, so force pods to pick up the freshly loaded image
$K -n "$NS" rollout restart deployment/inventory deployment/orders
for d in inventory orders; do
  $K -n "$NS" rollout status "deployment/$d" --timeout=120s
done

echo "==> Smoke test"
for i in $(seq 1 20); do
  curl -fsS http://127.0.0.1:9001/healthz >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://127.0.0.1:9001/low-stock; echo
curl -fsS -X POST http://127.0.0.1:9002/orders -H "Content-Type: application/json" \
  -d '{"sku":"paracetamol-500","qty":1}'; echo

helm --kube-context "$CTX" -n "$NS" list
$K -n "$NS" get pods -o wide
echo
echo "Inventory: http://127.0.0.1:9001/docs"
echo "Orders:    http://127.0.0.1:9002/docs"
