#!/usr/bin/env bash
# submit.sh — validate, then submit an sbatch file that already sits on the cluster.
# Usage: scripts/submit.sh <remote dir (relative to PROJECTS_DIR)> <file.sbatch> [--go]
# Without --go it runs `sbatch --test-only` (SLURM checks account/qos/resources without queueing) and the
# submission-cap check. Run scripts/estimate_cost.sh for the cost. With --go it submits and prints the job id.
# Always creates the logs dir first. <remote dir> may be absolute.
set -euo pipefail
source "$(dirname "$0")/_env.sh"
DIR="${1:-}"; FILE="${2:-}"; GO=0; [[ "${3:-}" == "--go" ]] && GO=1
[[ -n "$DIR" && -n "$FILE" ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[[ "$DIR" = /* ]] && DIR_ABS="$DIR" || DIR_ABS="${PROJECTS_DIR}/${DIR}"
rm -f .last_job_id            # never let a failed submit leave an older job id behind for the next step to read
on_login mkdir -p "${SCRATCH_DIR}/logs" "${SCRATCH_DIR}/runs"
echo "== test-only =="
on_login "cd '${DIR_ABS}' && sbatch --test-only '${FILE}'" || { echo "sbatch rejected the file; fix it before --go" >&2; exit 3; }
# exact task count for any SLURM array spec: 0-9, 0-9%4, 0,5,9, 1-10:2, or none (= 1 job)
TASKS="$(on_login "cat '${DIR_ABS}/${FILE}'" | python3 -c '
import re, sys
m = re.search(r"^#SBATCH --array=([0-9,\-:]+)", sys.stdin.read(), re.M)
if not m: print(1); sys.exit()
n = 0
for part in m.group(1).split(","):
    step = 1
    if ":" in part: part, step = part.split(":"); step = int(step)
    if "-" in part: a, b = map(int, part.split("-")); n += len(range(a, b + 1, step))
    else: n += 1
print(n)')"
# the cap belongs to the QoS named IN THE FILE and counts only jobs in THAT QoS (MaxSubmitPU is per QoS per user):
# a pending production array must not block a debug smoke
FILE_QOS="$(on_login "cat '${DIR_ABS}/${FILE}'" | grep -oE '^#SBATCH --qos=[A-Za-z0-9_]+' | head -1 | cut -d= -f2 || true)"
CAP="${QOS_MAX_SUBMIT:-}"; [[ "$FILE_QOS" == "${QOS_DEBUG:-}" ]] && CAP="${QOS_DEBUG_MAX_SUBMIT:-}"
QUEUED="$(on_login "squeue -r -h -u '${CLUSTER_USER}' ${FILE_QOS:+-q '${FILE_QOS}'} | wc -l" | tr -d ' ')"
echo "queued now in ${FILE_QOS:-?} (array tasks counted individually): ${QUEUED}; this submission adds ${TASKS}; per-user cap: ${CAP:-unknown}"
if [[ -n "${CAP}" && "${CAP}" =~ ^[0-9]+$ && $((QUEUED + TASKS)) -gt "${CAP}" ]]; then
  echo "ERROR: ${QUEUED}+${TASKS} exceeds the cap ${CAP} of ${FILE_QOS}. The whole submission is rejected, not trimmed. Fewer tasks, another QoS, or wait for the queue to drain." >&2; exit 3
fi
if [[ $GO -eq 0 ]]; then echo "dry run only. Re-run with --go to submit."; exit 0; fi
echo "== submit =="
OUT="$(on_login "cd '${DIR_ABS}' && sbatch '${FILE}'")"
echo "$OUT"
JOB_ID="$(echo "$OUT" | grep -oE '[0-9]+$' || true)"
[[ -n "$JOB_ID" ]] || { echo "no job id in sbatch output" >&2; exit 3; }
echo "$JOB_ID" > .last_job_id
echo "job ${JOB_ID} queued. Watch it: scripts/status.sh ${JOB_ID}"
