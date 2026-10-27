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
echo "== the job about to be submitted (4 cores, 5 min wall, debug queue) =="; grep -E "^#SBATCH" "$BUILD/smoke.sbatch"
"$HERE/estimate_cost.sh" --cpus 4 --hours 0.084 | tail -3
"$HERE/sync_push.sh" smoke "$BUILD/smoke.sbatch" "$BUILD/smoke_job.py"
"$HERE/submit.sh" smoke smoke.sbatch --go
JOB_ID="$(cat .last_job_id)"
echo "waiting for job ${JOB_ID} (debug queue; usually minutes)"
STATE=""; DONE=0
for _ in $(seq 1 120); do
  STATE="$(on_login "sacct -j '${JOB_ID}' -X -n -o State" 2>/dev/null | head -1 | tr -d ' ' || true)"   # one ssh hiccup must not end the wait
  case "$STATE" in
    COMPLETED|FAILED|TIMEOUT|CANCELLED*|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE) DONE=1; break ;;
    *) printf '.'; sleep 15 ;;
  esac
done
echo; echo "state=${STATE:-unknown}"
if [[ $DONE -eq 0 ]]; then
  echo "Job ${JOB_ID} is still ${STATE:-queued} after 30 min (queue busy). Not pulling yet. Check later with: scripts/status.sh ${JOB_ID}; then: scripts/sync_pull.sh ${RESULTS_DIR}/smoke-${JOB_ID}" >&2; exit 4
fi
"$HERE/sync_pull.sh" "${RESULTS_DIR}/smoke-${JOB_ID}"
PULLED="$(ls -td pulled/smoke-"${JOB_ID}"-* | head -1)"
if [[ -f "${PULLED}/smoke_result.json" ]] && grep -q '"machine"' "${PULLED}/smoke_result.json"; then
  echo "SMOKE_VERIFIED: ${PULLED}/smoke_result.json"; python3 -c "import json;d=json.load(open('${PULLED}/smoke_result.json'));print({k:d.get(k) for k in ('hostname','python','machine','cpus_allocated_to_this_job','cpu_count_node','nvidia_smi')})"
else
  echo "SMOKE_NOT_VERIFIED: no smoke_result.json came back. Read the log: scripts/status.sh ${JOB_ID}; then: ssh ${CLUSTER_USER}@${LOGIN_HOST} cat ${SCRATCH_DIR}/logs/smoke-${JOB_ID}.err" >&2
  exit 3
fi
