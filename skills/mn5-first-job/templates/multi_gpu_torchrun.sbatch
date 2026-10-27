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
RUN_DIR="__SCRATCH_DIR__/runs/${SLURM_JOB_NAME}-__RUN_ID__"   # RUN_ID: chosen once per training run, reused on every resubmit of it (a requeued job must find its own checkpoints; a NEW run must not)
mkdir -p "${RUN_DIR}/checkpoints"; cd "${RUN_DIR}"
export XDG_CACHE_HOME="__SCRATCH_DIR__/cache/${SLURM_JOB_NAME}-__RUN_ID__"   # caches: explicit, off $HOME, and OUTSIDE the run dir so they are never copied to results
export HF_HOME="${XDG_CACHE_HOME}/hf" HF_HUB_CACHE="${XDG_CACHE_HOME}/hf/hub" TRITON_CACHE_DIR="${XDG_CACHE_HOME}/triton"
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1    # no internet on the node: a hub client that tries to phone home hangs, then fails
mkdir -p "${XDG_CACHE_HOME}"
NGPU="${SLURM_GPUS_ON_NODE:-__GPUS__}"
# How YOUR script takes a checkpoint directory and a resume switch. CKPT_FLAG="--checkpoint-dir" makes the job pass
# "--checkpoint-dir <run dir>/checkpoints"; RESUME_FLAG="--resume" is appended as is. Both may be empty (then a requeue
# restarts from scratch). An unknown flag kills a typical argparse script at once, so match your script exactly.
CKPT_FLAG="__CKPT_FLAG__"; RESUME_FLAG="__RESUME_FLAG__"
CKPT_OPTS=(); [[ -n "$CKPT_FLAG" ]] && CKPT_OPTS=("$CKPT_FLAG" "${RUN_DIR}/checkpoints")
echo "node=$(hostname) start=$(date -u +%FT%TZ) gpus=${NGPU} restart=${SLURM_RESTART_COUNT:-0}"
nvidia-smi
# A whole 4-GPU node can queue for a day while 2 GPUs are free in minutes. SLURM never grants fewer GPUs than
# --gres asks for: if your training keeps the effective batch constant (batch per GPU x GPUs x grad accumulation),
# you can RESUBMIT with --gres=gpu:2 and get the same result sooner.
# `|| rc=$?`: under `set -e` a failed srun would end the script here and strand the results on scratch.
rc=0; srun --ntasks=1 --cpus-per-task="${SLURM_CPUS_PER_TASK}" \
  singularity exec --nv \
    --bind "__PROJECTS_DIR__:__PROJECTS_DIR__" --bind "__SCRATCH_DIR__:__SCRATCH_DIR__" \
    "__SIF__" torchrun --standalone --nproc_per_node="${NGPU}" __ENTRYPOINT__ ${CKPT_OPTS[@]+"${CKPT_OPTS[@]}"} ${RESUME_FLAG} __ARGS__ || rc=$?
DEST="__RESULTS_DIR__/${SLURM_JOB_NAME}-__RUN_ID__"; mkdir -p "$DEST"
# rsync, not cp: a requeued job must not nest a second copy; checkpoints stay on scratch (many GB, resumable there).
# Write FINAL outputs (the model you keep) into the run directory itself, not under checkpoints/: only the run
# directory reaches results, and scratch is purged.
rsync -a --exclude checkpoints --exclude cache "${RUN_DIR}/" "$DEST/"
echo "end=$(date -u +%FT%TZ) rc=${rc}"
exit "${rc}"
