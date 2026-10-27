#!/usr/bin/env bash
# run_smoke.sh — the whole first loop, end to end: render, push, submit, wait, pull, verify.
# Usage: scripts/run_smoke.sh [--dry-run]
# Verdict is read from the ARTIFACT (smoke_result.json pulled back), not from an exit code.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SKILL="$(cd "$HERE/.." && pwd)"
source "$HERE/_env.sh"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
BUILD="build"; mkdir -p "$BUILD"
"$HERE/render.sh" "$SKILL/templates/smoke.sbatch" "$BUILD/smoke.sbatch"
cp "$SKILL/scripts/smoke_job.py" "$BUILD/smoke_job.py"
if [[ $DRY -eq 1 ]]; then
  echo "[dry-run] would push build/smoke.sbatch + smoke_job.py to ${PROJECTS_DIR}/smoke, submit on ${LOGIN_HOST} with qos ${QOS_DEBUG}, poll, pull ${RESULTS_DIR}/smoke-<id>"
  cat "$BUILD/smoke.sbatch"; exit 0
fi
"$HERE/sync_push.sh" smoke "$BUILD/smoke.sbatch" "$BUILD/smoke_job.py"
"$HERE/submit.sh" smoke smoke.sbatch --go
JOB_ID="$(cat .last_job_id)"
echo "waiting for job ${JOB_ID} (debug queue; usually minutes)"
for _ in $(seq 1 120); do
  STATE="$(on_login "sacct -j '${JOB_ID}' -X -n -o State" | head -1 | tr -d ' ')"
  case "$STATE" in
    COMPLETED|FAILED|TIMEOUT|CANCELLED*|OUT_OF_MEMORY|NODE_FAIL) break ;;
    *) printf '.'; sleep 15 ;;
  esac
done
echo; echo "state=${STATE:-unknown}"
"$HERE/sync_pull.sh" "${RESULTS_DIR}/smoke-${JOB_ID}"
PULLED="$(ls -td pulled/* | head -1)"
if [[ -f "${PULLED}/smoke_result.json" ]] && grep -q '"machine"' "${PULLED}/smoke_result.json"; then
  echo "SMOKE_VERIFIED: ${PULLED}/smoke_result.json"; python3 -c "import json;d=json.load(open('${PULLED}/smoke_result.json'));print({k:d[k] for k in ('hostname','python','machine','cpu_count_visible','nvidia_smi')})"
else
  echo "SMOKE_NOT_VERIFIED: no smoke_result.json came back. Read the log: scripts/status.sh ${JOB_ID}; then: ssh ${CLUSTER_USER}@${LOGIN_HOST} cat ${SCRATCH_DIR}/logs/smoke-${JOB_ID}.err" >&2
  exit 3
fi
