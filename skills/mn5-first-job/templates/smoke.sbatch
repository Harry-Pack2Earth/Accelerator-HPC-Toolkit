#!/bin/bash -l
# -l = login shell: without it `module load` is undefined and the job dies at the first module line.
# smoke.sbatch: first job. Rendered by scripts/render.sh from cluster.env (double-underscore tokens are filled in).
#SBATCH --job-name=smoke
#SBATCH --account=__PROJECT__
#SBATCH --qos=__QOS_DEBUG__
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:05:00
#SBATCH --output=__SCRATCH_DIR__/logs/%x-%j.out
#SBATCH --error=__SCRATCH_DIR__/logs/%x-%j.err
# The logs directory must exist BEFORE sbatch, or the job dies with no output anywhere.
set -euo pipefail
export SRUN_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}"   # belt: srun inheritance from #SBATCH is unreliable here; braces: flag on srun too
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
RUN_DIR="__SCRATCH_DIR__/runs/${SLURM_JOB_NAME}-${SLURM_JOB_ID}"   # one directory per job, never shared
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
cp "__PROJECTS_DIR__/smoke/smoke_job.py" .
echo "node=$(hostname) start=$(date -u +%FT%TZ) cpus=${SLURM_CPUS_PER_TASK}"
nvidia-smi || echo "(this job requested no GPU, so none is visible; expected for the smoke)"
# Pass --cpus-per-task to srun explicitly: on this cluster srun does not inherit it from #SBATCH.
srun --ntasks=1 --cpus-per-task="${SLURM_CPUS_PER_TASK}" python3 smoke_job.py
DEST="__RESULTS_DIR__/${SLURM_JOB_NAME}-${SLURM_JOB_ID}"; mkdir -p "$DEST"
rsync -a "${RUN_DIR}/" "$DEST/"        # scratch job dirs are not backed up; results go to RESULTS_DIR (projects, or scratch/results on a tiny quota)
echo "end=$(date -u +%FT%TZ)"
