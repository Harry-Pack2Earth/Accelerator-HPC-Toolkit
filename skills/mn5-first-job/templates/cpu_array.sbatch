#!/bin/bash -l
# -l = login shell: without it `module load` is undefined and the job dies at the first module line.
# cpu_array.sbatch: N independent CPU tasks, one per line of a manifest file. No GPU requested.
# On a GPU-only allocation these still run on the accelerated partition, without a GPU.
#SBATCH --job-name=__JOB_NAME__
#SBATCH --account=__PROJECT__
#SBATCH --qos=__QOS__
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=__CPUS__          # cores per task; 8 is a sane start for scikit-learn / boosted trees
#SBATCH --time=__WALLTIME__
#SBATCH --array=0-__LAST__%__CONCURRENT__ # EVERY array task counts against the per-user submission cap
#SBATCH --output=__SCRATCH_DIR__/logs/%x-%A_%a.out
#SBATCH --error=__SCRATCH_DIR__/logs/%x-%A_%a.err
set -euo pipefail
export SRUN_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}"   # belt: srun inheritance from #SBATCH is unreliable here; braces: flag on srun too
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
MANIFEST="__MANIFEST__"                   # one argument string per line; task i runs line i
LINE="$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "${MANIFEST}")"
[[ -n "${LINE}" ]] || { echo "no manifest line for task ${SLURM_ARRAY_TASK_ID}"; exit 1; }
RUN_DIR="__SCRATCH_DIR__/runs/${SLURM_JOB_NAME}-${SLURM_ARRAY_JOB_ID}/${SLURM_ARRAY_TASK_ID}"
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
echo "node=$(hostname) task=${SLURM_ARRAY_TASK_ID} line='${LINE}' start=$(date -u +%FT%TZ)"
# Offline venv built by scripts/install_wheels_remote.sh (no internet on the nodes, nothing pip-installs here)
VENV="$(readlink -f "__VENV_DIR__/current")"   # resolved at start: a later install_wheels.sh never changes this job's venv
[[ -f "${VENV}/.ready" ]] || { echo "venv not ready: run scripts/install_wheels.sh from the laptop first"; exit 1; }
# load the SAME python module the venv was built with (the venv's python is a link into that module tree)
PY_MODULE="$(cat "${VENV}/.python_module")"
module load "$PY_MODULE" 2>/dev/null || module load intel mkl "$PY_MODULE"
unset PYTHONHOME PYTHONPATH          # the module exports these and they shadow the venv
source "${VENV}/bin/activate"
# `|| rc=$?`: under `set -e` a failed srun would end the script here and strand the results on scratch.
rc=0; srun --ntasks=1 --cpus-per-task="${SLURM_CPUS_PER_TASK}" python __ENTRYPOINT__ ${LINE} || rc=$?
DEST="__RESULTS_DIR__/${SLURM_JOB_NAME}-${SLURM_ARRAY_JOB_ID}/${SLURM_ARRAY_TASK_ID}"; mkdir -p "$DEST"
rsync -a "${RUN_DIR}/" "$DEST/"
echo "end=$(date -u +%FT%TZ) rc=${rc}"
exit "${rc}"
