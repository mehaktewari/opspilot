#!/usr/bin/env bash
# Add Prometheus + Grafana to the local cluster through Argo CD.
#   bash scripts/monitoring-up.sh      (after cluster-up.sh and argocd-up.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

CTX=kind-opspilot
K="kubectl --context $CTX"

$K -n argocd get application opspilot-dev >/dev/null 2>&1 \
  || { echo "Argo CD isn't set up. Run: bash scripts/cluster-up.sh && bash scripts/argocd-up.sh"; exit 1; }

# Prometheus + Grafana need roughly 400-500 MB more.
MIN_FREE_MB="${MIN_FREE_MB:-800}" WARN_FREE_MB="${WARN_FREE_MB:-1500}" bash scripts/preflight.sh

echo "==> Registering Prometheus and Grafana with Argo CD"
$K apply -f deploy/argocd/monitoring.yaml

echo "==> Waiting for both to sync (first time pulls images: 2-5 minutes)"
for app in prometheus grafana; do
  s=""
  for i in $(seq 1 72); do
    s=$($K -n argocd get application "$app" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
    [ "$s" = "Synced/Healthy" ] && break
    sleep 5
  done
  echo "  $app: ${s:-unknown}"
  [ "$s" = "Synced/Healthy" ] || { echo "  $app did not become healthy:"; $K -n monitoring get pods; exit 1; }
done

PASS=$($K -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d)
cat <<MSG

Monitoring is up.

Grafana (dashboards):
  kubectl --context $CTX -n monitoring port-forward svc/grafana 3000:80
  http://localhost:3000   user: admin   password: $PASS
  Dashboards -> OpsPilot -> "OpsPilot: service health"

Prometheus (raw metrics, alerts):
  kubectl --context $CTX -n monitoring port-forward svc/prometheus-server 9090:80
  http://localhost:9090/alerts

Make some traffic so the graphs have data:
  bash scripts/load.sh
MSG
