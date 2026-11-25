#!/usr/bin/env bash
# Delete the local kind cluster (frees CPU, RAM and disk).
set -euo pipefail
kind delete cluster --name opspilot
