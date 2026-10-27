---
name: mn5-first-job
description: Takes a new BSC MareNostrum 5 user from "I have an account" to a first job run, verified and pulled back, then to real GPU and CPU-array jobs. Use whenever the task mentions BSC, MareNostrum, MN5, the BSC AI Factory, EuroHPC, a supercomputer, HPC, SLURM, sbatch, a GPU allocation, Apptainer/Singularity on a cluster, or moving a training or data job from a laptop or cloud GPU to a cluster. Built from one startup's first two allocations; the rules carry what actually happened, and the few taken from site guidance without an incident are marked as such.
---

# mn5-first-job

You are operating a supercomputer on behalf of someone who may never have used one, possibly
never used a terminal. You do the cluster work over SSH. They approve, read, and decide.
The cluster is a shared public machine with a budget attached to this user's name: a mistake
costs real allocation hours and other people's queue time. Follow the procedure in order. Do not skip steps.
The scripts run on stock macOS `/bin/bash` 3.2, Linux bash and WSL2.

## The mental model (read once)

```
laptop (you + the human)                 BSC
────────────────────────                 ────────────────────────────────────────────────
scripts/preflight.sh  ──ssh──▶  login node   (glogin* = CPU partition, alogin* = GPU partition)
                                            submit with sbatch, watch with squeue/sacct, NEVER compute here
scripts/sync_push.sh  ──rsync─▶ transfer node (transfer1-4.bsc.es)   all data movement starts on the laptop
                                            ▼
                                GPFS, visible from every node:
                                  /gpfs/home/<proj>/<user>      tiny, shared, never run from here
                                  /gpfs/projects/<proj>/<user>  durable: code, small results (big files too, if the quota allows)
                                  /gpfs/scratch/<proj>/<user>   fast, not backed up, purged: job I/O, logs, and on a tiny
                                                                projects quota also images, wheels, venv, results
                                            ▼
                                compute nodes: run your job when the queue reaches it. No internet. No root.
scripts/sync_pull.sh  ◀─rsync──  results from RESULTS_DIR (preflight decides: projects, or scratch on a tiny quota)
```

A supercomputer is a queue, not a server. A job is a script that runs unattended when a slot frees
up, minutes or a day later. Everything it needs must be on GPFS before you submit.

## Procedure

All scripts run from one working folder on the laptop that holds `cluster.env`. Paths below are
relative to this skill's folder.

### Step 0. Preflight (laptop side, once per machine)

```
scripts/preflight.sh --user <cluster username>
```

It checks ssh and rsync, proves KEY-BASED login works (password prompts make every unattended
step fail while exiting 0), discovers the project code, queues, quota, budget and QoS limits with
BSC's own commands, and writes `cluster.env`: hosts, project, QoS names and limits, `PYTHON_MODULE`,
and the directories every script and template uses (`PROJECTS_DIR`, `SCRATCH_DIR`, `IMAGES_DIR`,
`WHEELS_DIR`, `VENV_DIR`, `RESULTS_DIR`). On a tiny projects quota (one real allocation had 512 MB)
images, wheels, venv and results go under scratch, and preflight says so: pull results promptly. Read its NOTE lines to the human. If login fails, the
human must create a key and upload it in the BSC accounts portal; the upload REPLACES the
authorized_keys file, so every key still wanted goes in the same upload. If the allocation shows
only `acc_*` queues it is GPU-only; preflight switches itself to an ACC login node and records it. If the account
has several allocations it stops and asks which one (`--project`).

### Step 1. Smoke (prove the loop before any real software)

```
scripts/run_smoke.sh
```

Renders `templates/smoke.sbatch`, pushes a standard-library-only Python job, submits it on the
debug queue, waits, pulls the result back, and declares `SMOKE_VERIFIED` only when
`smoke_result.json` is on the laptop. The verdict comes from the artifact, never from an exit code.
Show the human the JSON: hostname, Python version, `x86_64`, visible CPUs, `nvidia-smi` line.
If it is not verified, read the `.err` log before changing anything.

### Step 2. Software: pick one of three doors (see references/software-three-doors.md)

1. **Site modules** (`module avail`): fine for a quick stdlib or system-Python job.
2. **Offline wheel bundle into a venv on GPFS**: CPU work in Python (scikit-learn, boosted trees,
   data processing). `scripts/build_wheels.sh` on the laptop, then `scripts/install_wheels.sh <bundle>`,
   which pushes it and builds the venv once on the login node (rebuilds only when the bundle's content
   hash changes). Jobs test `VENV_DIR/.ready`.
3. **Apptainer image built off the cluster**: anything with a GPU. `scripts/build_sif.sh` on the
   laptop (or any machine with Docker or Apptainer), then `scripts/sync_push.sh IMAGES_DIR <file.sif> --verify`
   (the literal name `IMAGES_DIR`; the script resolves it from `cluster.env`), then prove it with
   `templates/image_smoke.sbatch` on the debug queue. The cluster is x86_64: an ARM laptop must
   build `linux/amd64`, and import checks inside that emulated build can fail falsely. The image
   is proven only by the image smoke on a GPU node.

Nothing installs on the cluster: no internet, no root. Code inside an image is frozen until the
image is rebuilt and re-pushed, and a stale image runs old code with no error.

Working folder for doors 2 and 3 (the build scripts run from it): `requirements.txt` (copy
`templates/requirements.example.txt`), `src/` with your code, and for door 3 a copy of `templates/container.def`
plus `templates/Dockerfile`. On macOS keep it under your home folder.

### Step 3. The real job

Render a template (`scripts/render.sh <template> <out> KEY=VALUE ...`), push, validate with
`scripts/submit.sh <dir> <file>` (runs `sbatch --test-only` and the submission-cap check of the QoS in the
file), show the human the cost (`scripts/estimate_cost.sh`) against the budget in `scripts/status.sh`, and only
then `--go`. Values from `cluster.env` fill in by themselves; the rest you pass:

| Template | KEY=VALUE you must pass |
|---|---|
| `smoke.sbatch` | none (`run_smoke.sh` does it) |
| `image_smoke.sbatch` | `CPUS` (= CORES_PER_GPU), `SIF` (absolute path on the cluster) |
| `single_gpu.sbatch` | `JOB_NAME`, `QOS` (`QOS_DEBUG` to test, `QOS_PROD` to run), `CPUS`, `WALLTIME` (HH:MM:SS), `SIF`, `ENTRYPOINT` (absolute, e.g. `/opt/app/src/train.py`), `ARGS` (may be empty) |
| `multi_gpu_torchrun.sbatch` | the above plus `GPUS` (2-4), `RUN_ID` (one per training run, reused on resubmits), `CKPT_FLAG` (your script's checkpoint-dir flag, e.g. `--checkpoint-dir`, or empty) and `RESUME_FLAG` (e.g. `--resume`, or empty); the job appends its own checkpoint path |
| `cpu_array.sbatch` | `JOB_NAME`, `QOS`, `CPUS` (per task), `WALLTIME`, `LAST` (last task index), `CONCURRENT`, `MANIFEST` (absolute), `ENTRYPOINT` (absolute), `ARGS`; `VENV_HASH` fills itself from `./.venv_hash` after `install_wheels.sh` |

- `templates/single_gpu.sbatch`: one GPU, one container, one entry point.
- `templates/multi_gpu_torchrun.sbatch`: 2 to 4 GPUs on ONE node, requeue + resume from checkpoint. Only the run
  directory minus `checkpoints/` and `cache/` is copied to results: a final model must be written to the run
  directory itself, not under `checkpoints/` (which stays on purged scratch).
- `templates/cpu_array.sbatch`: N independent CPU tasks from a manifest file; no GPU requested.

Start every new job shape on the debug queue with a tiny input (one job at a time there: it allows a single
submitted job per user, so a smoke and an image smoke go one after the other, and an array test there has one task).
Then production QoS.

### Step 4. Watch, pull, read

`scripts/status.sh [job id]`, then `scripts/sync_pull.sh <job dir>` (a name under `RESULTS_DIR`, wherever preflight put it). On any failure read
the `.err` log first; a job that died at the wall still printed its verdicts before it died.
TIMEOUT means resubmit the same job with a wall sized from the measured progress, not a new tool.

## Guardrails (non-negotiable with a non-expert human)

- Never submit without `sbatch --test-only` passing and the cost shown to the human.
- Never delete on GPFS without listing first, and never `rm -rf` a path you did not create this session.
  `sync_push.sh --mirror` lists what it would delete and stops; show the human, then add `--confirm-delete`.
  (The toolkit never uses `--mirror` on its own.)
- Never `scancel -u <user>` on your own initiative; ask. Cancelling and resubmitting doubles the spend.
- Never run anything heavier than `ls`, `cat`, `squeue` on a login node, and never from `/gpfs/home`. The one
  exception is the venv build by `install_wheels.sh` (a pip install of pre-built wheels: seconds, no network).
- Never change an sbatch file, image, wheel bundle or dataset that a queued or running job reads.
- Never pass lists through `sbatch --export` (it splits on commas); render values into the file.
- Never leave a job with no checkpoint on a wall longer than two hours.
- When something goes wrong on the queue, stop, cancel what is yours, redesign once, resubmit once.
  Do not patch a live queue twice.
- When the human must paste a command block themselves: one fenced block, commands only, `cd` first.
  If their pasted output stops early, assume the trailing commands never ran.

## Rules of the house, each one earned

The full list with what actually happened is `references/lessons.md`. The ones that bite in week one:

1. Compute and login nodes have no outbound internet. Stage everything.
2. `#!/bin/bash -l` on every batch script, or `module` is undefined.
3. Pass `--cpus-per-task` to `srun` explicitly; it does not inherit from `#SBATCH` here.
4. The per-user submission cap counts every array task; one rejected send aborts the whole chain.
5. A whole 4-GPU node can queue for a day; two GPUs are free in minutes. Make jobs GPU-count tolerant, then
   resubmit with fewer GPUs when a whole node will not start (SLURM never grants fewer than asked).
6. The project quota can be tiny on a new allocation. Check `bsc_quota` before the first push.
7. Verify an image's sha on the remote side; a 13 GB image once arrived as a 172 MB stub.
8. Keep every cache off `$HOME` and set each one explicitly; container defaults resolve elsewhere.
9. One directory per job and per task. Shared paths race on GPFS; `flock` does not help across nodes.
10. The H100s on this system have 64 GB, not 80.

## Verification status

What has been run on which machine lives in one place: `TESTING.md` at the repository root. Nothing else in this
skill states a verification status; if a sentence here and that table disagree, the table wins.

## Files

- `scripts/`: `preflight.sh`, `run_smoke.sh`, `render.sh`, `sync_push.sh`, `sync_pull.sh`, `submit.sh`,
  `status.sh`, `estimate_cost.sh`, `build_sif.sh`, `build_wheels.sh`, `install_wheels.sh` (laptop side; runs
  `install_wheels_remote.sh` on the login node), `smoke_job.py`
- `templates/`: `smoke.sbatch`, `image_smoke.sbatch`, `single_gpu.sbatch`, `multi_gpu_torchrun.sbatch`,
  `cpu_array.sbatch`, `container.def` + `Dockerfile` (same image, keep them in step), `requirements.example.txt`,
  `ssh_config.example`
- `references/`: `lessons.md` (what happened, by class), `bsc-marenostrum5.md` (site facts, labelled
  measured / documented / unverified), `software-three-doors.md` (modules, wheels, images, per-OS builds),
  `troubleshooting.md` (symptom → cause → fix), `budget-and-queues.md` (billing, caps, walls, cost arithmetic)

Load a reference when its topic comes up; `lessons.md` before any production submission.
