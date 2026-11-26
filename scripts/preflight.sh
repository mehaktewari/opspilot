#!/usr/bin/env bash
# Check the machine has room before starting the cluster. Sourced by cluster-up.sh.
#   bash scripts/preflight.sh            # check only
#   FORCE=1 bash scripts/cluster-up.sh   # start anyway
set -uo pipefail

MIN_FREE_MB="${MIN_FREE_MB:-1500}"     # below this, refuse to start (unless FORCE=1)
WARN_FREE_MB="${WARN_FREE_MB:-2500}"   # below this, warn
MIN_DISK_GB="${MIN_DISK_GB:-15}"

[ -n "${CI:-}" ] && { echo "preflight: CI runner, skipping"; exit 0; }

free_mb=""
if command -v powershell.exe >/dev/null 2>&1; then          # Windows (Git Bash)
  kb=$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory" 2>/dev/null | tr -dc '0-9')
  [ -n "$kb" ] && free_mb=$((kb / 1024))
  disk_gb=$(powershell.exe -NoProfile -Command "[math]::Floor((Get-PSDrive C).Free/1GB)" 2>/dev/null | tr -dc '0-9')
elif [ -r /proc/meminfo ]; then                              # Linux
  free_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  disk_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
elif command -v vm_stat >/dev/null 2>&1; then                # macOS (rough)
  pages=$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
  free_mb=$((pages * 4096 / 1024 / 1024))
  disk_gb=$(df -g / | tail -1 | awk '{print $4}')
fi

echo "==> Preflight: free RAM ${free_mb:-?} MB, free disk ${disk_gb:-?} GB"

if [ -n "${disk_gb:-}" ] && [ "$disk_gb" -lt "$MIN_DISK_GB" ]; then
  echo "  WARNING: under ${MIN_DISK_GB} GB disk free. Try: docker system prune -f"
fi

if [ -n "$free_mb" ] && [ "$free_mb" -lt "$WARN_FREE_MB" ]; then
  echo "  Low memory. Close VMware/VirtualBox VMs, extra browser tabs and heavy apps."
  if command -v tasklist.exe >/dev/null 2>&1; then
    echo "  Biggest memory users right now:"
    tasklist.exe /FO CSV /NH 2>/dev/null | tr -d '\r' | awk -F'","' '{gsub(/"/,"",$1); m=$5; gsub(/[^0-9]/,"",m); print m "\t" $1}' \
      | sort -rn | head -5 | awk -F'\t' '{printf "    %6d MB  %s\n", $1/1024, $2}'
  fi
  if [ "$free_mb" -lt "$MIN_FREE_MB" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "  Refusing to start with under ${MIN_FREE_MB} MB free (pods would get killed)."
    echo "  Free some memory, or run with FORCE=1 to start anyway."
    exit 1
  fi
fi
exit 0
