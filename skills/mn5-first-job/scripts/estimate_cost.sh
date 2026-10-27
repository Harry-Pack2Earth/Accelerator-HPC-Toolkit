#!/usr/bin/env bash
# estimate_cost.sh — what a job will cost before you submit it.
# Usage: scripts/estimate_cost.sh --gpus N --hours H [--tasks T] [--cores-per-gpu C] [--cpus N (cpu-only tasks)]
# Billing on the accelerated partition is in CPU-hours at CORES_PER_GPU per GPU (default from cluster.env).
# A 5,000 GPU-hour allocation is 100,000 of those CPU-hours at 20 cores per GPU.
set -euo pipefail
GPUS=0; HOURS=""; TASKS=1; CPUS=""; CPG="${CORES_PER_GPU:-20}"
[[ -f "${HPC_ENV:-cluster.env}" ]] && CPG="$(grep -E '^CORES_PER_GPU=' "${HPC_ENV:-cluster.env}" | cut -d= -f2 || echo 20)"
while [[ $# -gt 0 ]]; do case "$1" in
  --gpus) GPUS="$2"; shift 2 ;; --hours) HOURS="$2"; shift 2 ;; --tasks) TASKS="$2"; shift 2 ;;
  --cores-per-gpu) CPG="$2"; shift 2 ;; --cpus) CPUS="$2"; shift 2 ;;
  *) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac; done
[[ -n "$HOURS" ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
python3 - "$GPUS" "$HOURS" "$TASKS" "$CPG" "${CPUS:-0}" <<'PY'
import sys
gpus, hours, tasks, cpg, cpus = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
if gpus > 0:
    gpu_h = gpus * hours * tasks
    print(f"GPU-hours: {gpu_h:,.1f}  (= {gpus:g} GPU x {hours:g} h x {tasks} task(s))")
    print(f"billed CPU-hours: {gpu_h * cpg:,.0f}  at {cpg:g} cores per GPU")
    print(f"share of a 5,000 GPU-h allocation: {100 * gpu_h / 5000:.1f}%")
else:
    cpu_h = cpus * hours * tasks
    print(f"CPU-hours: {cpu_h:,.1f}  (= {cpus:g} cores x {hours:g} h x {tasks} task(s))")
    print(f"GPU-hour equivalent: {cpu_h / cpg:,.1f}  at {cpg:g} cores per GPU")
    print(f"share of a 5,000 GPU-h allocation: {100 * (cpu_h / cpg) / 5000:.1f}%")
print("Compare with the remaining budget in `bsc_acct` (scripts/status.sh) before submitting.")
PY
