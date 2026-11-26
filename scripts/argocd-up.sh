#!/usr/bin/env bash
# Install Argo CD into the local kind cluster and hand the app over to GitOps.
#   bash scripts/argocd-up.sh        (run scripts/cluster-up.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."

ARGOCD_VERSION=v3.6.3
CTX=kind-opspilot           # never touches any other cluster
K="kubectl --context $CTX"

$K get nodes >/dev/null 2>&1 || { echo "kind cluster not running. Run: bash scripts/cluster-up.sh"; exit 1; }

echo "==> Installing Argo CD $ARGOCD_VERSION"
$K create namespace argocd --dry-run=client -o yaml | $K apply -f -
# --server-side: Argo CD's CRDs are too large for client-side apply
$K apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"

echo "==> Slimming Argo CD for a laptop"
# Not used locally: SSO (dex), notifications, ApplicationSets. Login as admin still works.
$K -n argocd scale deployment argocd-dex-server argocd-notifications-controller \
  argocd-applicationset-controller --replicas=0
# Upstream ships with no limits at all; cap each component so it can't starve the node.
$K -n argocd set resources statefulset/argocd-application-controller -c argocd-application-controller \
  --requests=cpu=100m,memory=256Mi --limits=cpu=500m,memory=768Mi
$K -n argocd set resources deployment/argocd-repo-server -c argocd-repo-server \
  --requests=cpu=50m,memory=128Mi --limits=cpu=500m,memory=512Mi
$K -n argocd set resources deployment/argocd-server -c argocd-server \
  --requests=cpu=50m,memory=96Mi --limits=cpu=300m,memory=256Mi
$K -n argocd set resources deployment/argocd-redis -c redis \
  --requests=cpu=25m,memory=32Mi --limits=cpu=200m,memory=128Mi

$K -n argocd rollout status deployment/argocd-server --timeout=300s
$K -n argocd rollout status deployment/argocd-repo-server --timeout=300s
$K -n argocd rollout status deployment/argocd-redis --timeout=300s
$K -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

# Argo CD now owns the app. Remove the Helm release record so two tools don't both manage it.
# (--keep-history is not needed: the running pods stay; Argo CD adopts them on first sync.)
if helm --kube-context "$CTX" -n opspilot status opspilot >/dev/null 2>&1; then
  echo "==> Handing over from Helm to Argo CD"
  $K -n opspilot delete secret -l owner=helm,name=opspilot
fi

echo "==> Registering the dev application"
$K apply -f deploy/argocd/opspilot-dev.yaml

echo "==> Waiting for first sync"
for i in $(seq 1 60); do
  s=$($K -n argocd get application opspilot-dev -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
  echo "  $s"
  [ "$s" = "Synced/Healthy" ] && break
  sleep 5
done
[ "$s" = "Synced/Healthy" ] || { echo "Application did not become Synced/Healthy"; $K -n argocd get application opspilot-dev -o yaml | tail -40; exit 1; }

PASS=$($K -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
cat <<MSG

Argo CD is managing OpsPilot (Synced/Healthy).

Open the UI:
  kubectl --context $CTX -n argocd port-forward svc/argocd-server 8080:443
  https://localhost:8080   (accept the self-signed certificate warning)
  user: admin   password: $PASS
MSG
