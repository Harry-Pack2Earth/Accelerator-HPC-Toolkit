#!/bin/bash -l
# image_smoke.sbatch: prove a freshly pushed image on ONE GPU, debug queue, before any real job uses it.
# A broken or stale image fails here in ~10 s instead of killing a fleet. Images cannot be tested on the
# login node (singularity exec fails there for want of /scratch/tmp); only a compute node counts.
#SBATCH --job-name=image-smoke
#SBATCH --account=__PROJECT__
#SBATCH --qos=__QOS_DEBUG__
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=__CPUS__
#SBATCH --time=00:10:00
#SBATCH --output=__SCRATCH_DIR__/logs/%x-%j.out
#SBATCH --error=__SCRATCH_DIR__/logs/%x-%j.err
set -euo pipefail
export SRUN_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}"
module load __CONTAINER_MODULE__
echo "node=$(hostname) image=__SIF__ sha=$(sha256sum "__SIF__" | cut -c1-16)"
# No pipes into head/grep here: under `set -o pipefail` a closed pipe kills nvidia-smi with SIGPIPE and the job
# exits 13 before srun runs. Ask for exactly what you want instead.
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
srun --ntasks=1 --cpus-per-task="${SLURM_CPUS_PER_TASK}" singularity exec --nv "__SIF__" \
  python -c "import platform, torch; assert torch.cuda.is_available(), 'CUDA not available in the container'; print('IMAGE_OK', platform.machine(), torch.__version__, torch.version.cuda, torch.cuda.get_device_name(0))"
