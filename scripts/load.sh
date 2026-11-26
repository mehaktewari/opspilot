#!/usr/bin/env bash
# Send steady traffic to both services so dashboards and alerts have data.
#   bash scripts/load.sh          # 3 minutes
#   bash scripts/load.sh 600      # 10 minutes
set -uo pipefail

DURATION="${1:-180}"
INV="${INVENTORY_URL:-http://127.0.0.1:9001}"
ORD="${ORDERS_URL:-http://127.0.0.1:9002}"
SKUS=(paracetamol-500 cetirizine-10 amoxicillin-500 ors-sachet)

curl -fsS --max-time 3 "$INV/healthz" >/dev/null || { echo "inventory not reachable at $INV (is the cluster up?)"; exit 1; }

echo "==> Sending traffic for ${DURATION}s (Ctrl+C to stop)"
end=$(( $(date +%s) + DURATION ))
worker() {
  local n=0
  while [ "$(date +%s)" -lt "$end" ]; do
    sku=${SKUS[$((RANDOM % ${#SKUS[@]}))]}
    case $((n % 4)) in
      0|1) curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$INV/items/$sku" ;;
      2)   curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$INV/items" ;;
      3)   curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 -X POST "$ORD/orders" \
             -H 'Content-Type: application/json' -d "{\"sku\":\"$sku\",\"qty\":1}" ;;
    esac
    n=$((n + 1))
    sleep 0.3
  done
}
results=$(mktemp)
for w in 1 2 3; do worker >> "$results" & done
wait
total=$(wc -l < "$results")
echo "==> Done: $total requests"
sort "$results" | uniq -c | awk '{printf "    %6d  HTTP %s\n", $1, $2}'
rm -f "$results"
