#!/usr/bin/env bash
# estimate_cost.sh — what a job will cost before you submit it.
# Usage: scripts/estimate_cost.sh (--gpus N | --cpus N) --hours H [--tasks T] [--cores-per-gpu C] [--budget-gpu-hours B]
# --budget-gpu-hours defaults to the allocation preflight read from bsc_acct (cluster.env), else 5,000.
# Billing on the accelerated partition is in CPU-hours at CORES_PER_GPU per GPU (default from cluster.env).
# A 5,000 GPU-hour allocation is 100,000 of those CPU-hours at 20 cores per GPU.
set -euo pipefail
GPUS=0; HOURS=""; TASKS=1; CPUS=""; CPG="${CORES_PER_GPU:-20}"; BUDGET=5000; TOTAL_KH=""; USED_KH=""
ENV_FILE="${HPC_ENV:-cluster.env}"
if [[ -f "$ENV_FILE" ]]; then
  envval() { grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '"' || true; }   # last definition wins
  v="$(envval CORES_PER_GPU)"; [[ -n "$v" ]] && CPG="$v"
  TOTAL_KH="$(envval BUDGET_TOTAL_KH)"; USED_KH="$(envval BUDGET_USED_KH)"
  # the allocation's own size, when preflight read it: 1 khour = 1,000 CPU-hours = 1000/CPG GPU-hours
  if [[ "$TOTAL_KH" =~ ^[0-9.]+$ ]]; then BUDGET="$(python3 -c "print(float('$TOTAL_KH')*1000/float('$CPG'))")"; else TOTAL_KH=""; USED_KH=""; fi
fi
while [[ $# -gt 0 ]]; do case "$1" in
  --gpus) GPUS="$2"; shift 2 ;; --hours) HOURS="$2"; shift 2 ;; --tasks) TASKS="$2"; shift 2 ;;
  --cores-per-gpu) CPG="$2"; shift 2 ;; --cpus) CPUS="$2"; shift 2 ;; --budget-gpu-hours) BUDGET="$2"; shift 2 ;;
  *) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac; done
[[ -n "$HOURS" ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[[ "$GPUS" != 0 || -n "$CPUS" ]] || { echo "give --gpus N or --cpus N" >&2; exit 2; }
python3 - "$GPUS" "$HOURS" "$TASKS" "$CPG" "${CPUS:-0}" "$BUDGET" "${TOTAL_KH:-}" "${USED_KH:-}" <<'PY'
import sys
gpus, hours, tasks, cpg, cpus, budget = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
total_kh, used_kh = sys.argv[7], sys.argv[8]
if gpus > 0:
    gpu_h = gpus * hours * tasks
    print(f"GPU-hours: {gpu_h:,.1f}  (= {gpus:g} GPU x {hours:g} h x {tasks} task(s))")
    print(f"billed CPU-hours: {gpu_h * cpg:,.0f}  at {cpg:g} cores per GPU")
    print(f"share of a {budget:,.0f} GPU-h allocation: {100 * gpu_h / budget:.1f}%")
else:
    cpu_h = cpus * hours * tasks
    print(f"CPU-hours: {cpu_h:,.1f}  (= {cpus:g} cores x {hours:g} h x {tasks} task(s))")
    print(f"GPU-hour equivalent: {cpu_h / cpg:,.1f}  at {cpg:g} cores per GPU")
    print(f"share of a {budget:,.0f} GPU-h allocation: {100 * (cpu_h / cpg) / budget:.1f}%")
if total_kh and used_kh:
    rem_cpu = (float(total_kh) - float(used_kh)) * 1000
    job_cpu = gpu_h * cpg if gpus > 0 else cpu_h
    if rem_cpu > 0:
        print(f"remaining at the last accounting stamp: {rem_cpu:,.0f} CPU-hours = {rem_cpu / cpg:,.0f} GPU-hours; this job = {100 * job_cpu / rem_cpu:.1f}% of it (bsc_acct lags by hours; re-run preflight to refresh)")
    else:
        print(f"WARNING: the allocation reads as fully used ({used_kh} of {total_kh} khours at the last accounting stamp). Ask the human before submitting anything.")
else:
    print("Compare with the remaining budget in `bsc_acct` (scripts/status.sh) before submitting.")
PY
