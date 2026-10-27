#!/bin/bash -l
# -l = login shell: without it `module load` is undefined and the job dies at the first module line.
# single_gpu.sbatch: one GPU, one container, one Python entry point.
#SBATCH --job-name=__JOB_NAME__
#SBATCH --account=__PROJECT__
#SBATCH --qos=__QOS__
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=__CPUS__          # = CORES_PER_GPU x GPUs; the budget is billed on this
#SBATCH --time=__WALLTIME__               # HH:MM:SS. Too short = killed at the wall; checkpoint if long
#SBATCH --output=__SCRATCH_DIR__/logs/%x-%j.out
#SBATCH --error=__SCRATCH_DIR__/logs/%x-%j.err
set -euo pipefail
export SRUN_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}"   # belt: srun inheritance from #SBATCH is unreliable here; braces: flag on srun too
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
module load __CONTAINER_MODULE__
RUN_DIR="__SCRATCH_DIR__/runs/${SLURM_JOB_NAME}-${SLURM_JOB_ID}"
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
export XDG_CACHE_HOME="${RUN_DIR}/cache"       # every cache explicit and off $HOME; inside the container defaults resolve elsewhere
export HF_HOME="${XDG_CACHE_HOME}/hf" HF_HUB_CACHE="${XDG_CACHE_HOME}/hf/hub" TRITON_CACHE_DIR="${XDG_CACHE_HOME}/triton"
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1    # no internet on the node: a hub client that tries to phone home hangs, then fails
mkdir -p "${XDG_CACHE_HOME}"
echo "node=$(hostname) start=$(date -u +%FT%TZ) image=__SIF__"
nvidia-smi                                     # driver + CUDA header on the record, every run
# The container runs as you, not root; code and data must be readable by your uid.
# Code comes from the image: a stale .sif runs old code with no error. Rebuild + re-push after code changes.
# `|| rc=$?`: under `set -e` a failed srun would end the script here and strand the results on scratch.
rc=0; srun --ntasks=1 --cpus-per-task="${SLURM_CPUS_PER_TASK}" \
  singularity exec --nv \
    --bind "__PROJECTS_DIR__:__PROJECTS_DIR__" --bind "__SCRATCH_DIR__:__SCRATCH_DIR__" \
    "__SIF__" python __ENTRYPOINT__ __ARGS__ || rc=$?
mkdir -p "__RESULTS_DIR__"
cp -r "${RUN_DIR}" "__RESULTS_DIR__/"
echo "end=$(date -u +%FT%TZ) rc=${rc}"
exit "${rc}"
