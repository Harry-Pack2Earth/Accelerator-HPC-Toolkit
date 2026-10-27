#!/usr/bin/env bash
# status.sh — what is queued, what finished, what the budget looks like.
# Usage: scripts/status.sh [job id]
set -euo pipefail
source "$(dirname "$0")/_env.sh"
JOB="${1:-}"
echo "== queue (squeue) =="
on_login "squeue -u '${CLUSTER_USER}' -o '%.10i %.12j %.9P %.8T %.10M %.10l %.6D %R'"
echo "== last 24 h (sacct) =="
on_login "sacct -u '${CLUSTER_USER}' -S now-24hours -X --format=JobID,JobName%14,State,Elapsed,ExitCode,AllocTRES%40"
if [[ -n "$JOB" ]]; then
  echo "== job ${JOB} =="
  on_login "sacct -j '${JOB}' -X --format=JobID,JobName%14,State,Elapsed,ExitCode,NodeList,Reason; ls -la '${SCRATCH_DIR}/logs/' | grep -- '-${JOB}' || true"
fi
echo "== budget (bsc_acct) =="
on_login bsc_acct
