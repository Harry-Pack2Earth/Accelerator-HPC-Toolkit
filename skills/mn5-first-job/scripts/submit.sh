#!/usr/bin/env bash
# submit.sh — validate, then submit an sbatch file that already sits on the cluster.
# Usage: scripts/submit.sh <remote dir (relative to PROJECTS_DIR)> <file.sbatch> [--go]
# Without --go it runs `sbatch --test-only` (SLURM checks account/qos/resources without queueing) and prints
# the cost estimate. With --go it submits and prints the job id. Always creates the logs dir first.
set -euo pipefail
source "$(dirname "$0")/_env.sh"
DIR="${1:-}"; FILE="${2:-}"; GO=0; [[ "${3:-}" == "--go" ]] && GO=1
[[ -n "$DIR" && -n "$FILE" ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
rm -f .last_job_id            # never let a failed submit leave an older job id behind for the next step to read
on_login mkdir -p "${SCRATCH_DIR}/logs" "${SCRATCH_DIR}/runs"
echo "== test-only =="
on_login "cd '${PROJECTS_DIR}/${DIR}' && sbatch --test-only '${FILE}'" || { echo "sbatch rejected the file; fix it before --go" >&2; exit 3; }
QUEUED="$(on_login "squeue -r -h -u '${CLUSTER_USER}' | wc -l" | tr -d ' ')"
TASKS="$(grep -oE '^#SBATCH --array=[0-9]+-([0-9]+)' <(on_login "cat '${PROJECTS_DIR}/${DIR}/${FILE}'") | grep -oE '[0-9]+$' || echo 0)"
[[ "$TASKS" -gt 0 ]] && TASKS=$((TASKS + 1)) || TASKS=1
echo "queued now (array tasks counted individually): ${QUEUED}; this submission adds ${TASKS}; per-user cap: ${QOS_MAX_SUBMIT:-unknown}"
if [[ -n "${QOS_MAX_SUBMIT:-}" && "${QOS_MAX_SUBMIT}" =~ ^[0-9]+$ && $((QUEUED + TASKS)) -gt "${QOS_MAX_SUBMIT}" ]]; then
  echo "ERROR: ${QUEUED}+${TASKS} exceeds the cap ${QOS_MAX_SUBMIT}. The whole submission is rejected, not trimmed. Send a smaller batch after the queue drains." >&2; exit 3
fi
if [[ $GO -eq 0 ]]; then echo "dry run only. Re-run with --go to submit."; exit 0; fi
echo "== submit =="
OUT="$(on_login "cd '${PROJECTS_DIR}/${DIR}' && sbatch '${FILE}'")"
echo "$OUT"
JOB_ID="$(echo "$OUT" | grep -oE '[0-9]+$' || true)"
[[ -n "$JOB_ID" ]] || { echo "no job id in sbatch output" >&2; exit 3; }
echo "$JOB_ID" > .last_job_id
echo "job ${JOB_ID} queued. Watch it: scripts/status.sh ${JOB_ID}"
