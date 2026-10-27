#!/bin/bash -l
# -l = login shell: without it `module load` is undefined and the job dies at the first module line.
# multi_gpu_torchrun.sbatch: several GPUs on ONE node, one process per GPU (data parallel).
# Keep it single-node until a single node is proven too small; multi-node adds a whole class of failures.
#SBATCH --job-name=__JOB_NAME__
#SBATCH --account=__PROJECT__
#SBATCH --qos=__QOS__
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:__GPUS__
#SBATCH --cpus-per-task=__CPUS__          # = CORES_PER_GPU x GPUs
#SBATCH --time=__WALLTIME__
#SBATCH --requeue                         # if the node fails the job is resubmitted; your code must resume from its last checkpoint
#SBATCH --output=__SCRATCH_DIR__/logs/%x-%j.out
#SBATCH --error=__SCRATCH_DIR__/logs/%x-%j.err
set -euo pipefail
export SRUN_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}"   # belt: srun inheritance from #SBATCH is unreliable here; braces: flag on srun too
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
module load __CONTAINER_MODULE__
RUN_DIR="__SCRATCH_DIR__/runs/${SLURM_JOB_NAME}"      # NO job id here: a requeued job must find its own checkpoints
mkdir -p "${RUN_DIR}/checkpoints"; cd "${RUN_DIR}"
export XDG_CACHE_HOME="${RUN_DIR}/cache"       # every cache explicit and off $HOME; inside the container defaults resolve elsewhere
export HF_HOME="${XDG_CACHE_HOME}/hf" HF_HUB_CACHE="${XDG_CACHE_HOME}/hf/hub" TRITON_CACHE_DIR="${XDG_CACHE_HOME}/triton"
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1    # no internet on the node: a hub client that tries to phone home hangs, then fails
mkdir -p "${XDG_CACHE_HOME}"
NGPU="${SLURM_GPUS_ON_NODE:-__GPUS__}"
echo "node=$(hostname) start=$(date -u +%FT%TZ) gpus=${NGPU} restart=${SLURM_RESTART_COUNT:-0}"
nvidia-smi
# A whole 4-GPU node can queue for a day while 2 GPUs are free in minutes. If your training keeps the
# effective batch constant (batch per GPU x GPUs x grad accumulation), you can take whatever is offered.
srun --ntasks=1 --cpus-per-task="${SLURM_CPUS_PER_TASK}" \
  singularity exec --nv \
    --bind "__PROJECTS_DIR__:__PROJECTS_DIR__" --bind "__SCRATCH_DIR__:__SCRATCH_DIR__" \
    "__SIF__" torchrun --standalone --nproc_per_node="${NGPU}" __ENTRYPOINT__ \
      --checkpoint-dir "${RUN_DIR}/checkpoints" --resume __ARGS__
rc=$?
mkdir -p "__PROJECTS_DIR__/results"
cp -r "${RUN_DIR}" "__PROJECTS_DIR__/results/${SLURM_JOB_NAME}-${SLURM_JOB_ID}"
echo "end=$(date -u +%FT%TZ) rc=${rc}"
exit "${rc}"
