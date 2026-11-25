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

if $K -n argocd get application opspilot-dev >/dev/null 2>&1; then
  # After Day 6, Argo CD deploys from Git. Running helm here would fight it.
  echo "==> Argo CD manages the app (deploys from Git), skipping helm install"
else
  echo "==> helm upgrade --install"
  helm lint "$CHART"
  helm upgrade --install opspilot "$CHART" \
    --kube-context "$CTX" --namespace "$NS" \
    --wait --timeout 3m
fi
# Same :dev tag every time, so force pods to pick up the freshly loaded image
$K -n "$NS" rollout restart deployment/inventory deployment/orders
for d in inventory orders; do
  $K -n "$NS" rollout status "deployment/$d" --timeout=120s
done

echo "==> Smoke test"
# Right after a rollout, old pods are still terminating and can reset connections,
# so retry on any error instead of trusting the first response.
smoke() { curl -fsS --retry 15 --retry-delay 2 --retry-all-errors --max-time 5 "$@"; }
for port in 9001 9002; do
  smoke "http://127.0.0.1:$port/healthz" >/dev/null || { echo "Service on :$port never became healthy"; exit 1; }
done
smoke http://127.0.0.1:9001/low-stock; echo
smoke -X POST http://127.0.0.1:9002/orders -H "Content-Type: application/json" \
  -d '{"sku":"paracetamol-500","qty":1}'; echo

helm --kube-context "$CTX" -n "$NS" list 2>/dev/null || true
$K -n "$NS" get pods -o wide
echo
echo "Inventory: http://127.0.0.1:9001/docs"
echo "Orders:    http://127.0.0.1:9002/docs"
