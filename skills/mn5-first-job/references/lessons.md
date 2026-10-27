# Lessons, with what actually happened

Every entry below comes from a real incident in one startup's first two allocations on MareNostrum 5
(June to October 2026, about 500 submissions, 21,000 tasks, 7,000 GPU-hours). Nothing here is copied
from a manual. "Rule" is what to do; "Seen" is the evidence; "Fix" is what the team changed.
Items marked *documented, not seen* are site guidance the team followed without ever triggering it.

## Connect

1. **Rule:** Key-based SSH only. Password prompts make unattended steps fail silently.
   **Seen:** a background push "exited 0" after every ssh attempt died at the password prompt; nothing arrived.
   **Fix:** `ssh -o BatchMode=yes <user>@<host> hostname` must print the hostname before any script runs.
2. **Rule:** The portal key upload replaces the whole `authorized_keys`. Include every key you still want.
   **Seen:** BSC moved to portal-managed keys in October 2026 and announced the end of password login by end of 2026.
3. **Rule:** Ship command sequences and long lists as files, never as terminal pastes.
   **Seen:** a 1,094-character line lost chunks when pasted into the login node; a multi-block paste garbled; one
   submission ran on a truncated list and was cancelled while pending.
   **Fix:** lists rsync'd as files with a `wc -l` guard; sequences as scripts.
4. **Rule:** When a human pastes for you: one fenced block, commands only, `cd` first. Explanation above the block.
   **Seen:** a final submit placed after a prose line was never pasted; the final never ran; everything was cancelled.

## Transfer

5. **Rule:** Know which rsync you have. macOS ships openrsync (or rsync 2.6.9 on older systems).
   **Seen:** `--chown` and `--info=progress2` do not exist there. **Fix:** Homebrew rsync when present; `-P` otherwise.
6. **Rule:** Verify a large image's sha on the remote side before anything uses it.
   **Seen:** a 13.2 GB image arrived as a 172 MB stub; every job died at mount with a bad superblock.
7. **Rule:** A dataset push mirrors its source (`--delete`), or the remote becomes the union of every version pushed.
   **Seen:** files dropped locally survived remotely; three result sets reported three different counts.
8. **Rule:** A mutable remote data path carries an identity stamp (a VERSION file) that is read back before submit.
   **Seen:** a re-push silently repointed later runs; two result sets were compared as one experiment.
9. **Rule:** Never pull large re-derivable artifacts into timestamped pull directories.
   **Seen:** 25 copies of a 50 GB merged model = 872 GB on the laptop; a backup watcher then mirrored 951 GB to cloud storage.
10. **Rule:** rsync exit 23 for a missing optional source is normal. Handle it narrowly; remove empty staging dirs.
    **Seen:** under `set -e` a missing optional directory aborted the pull after results had already transferred, and
    the empty staging directory then "won" as the newest pull.
11. **Rule:** Logs written to the submit directory (relative `-o`) are not in your logs folder. Pull them explicitly.
    **Seen:** four failed tasks could only be diagnosed from state codes because the logs sat unreachable on the cluster.
12. **Rule:** Pull study and state databases with results; they size the next round's wall time.
13. **Rule:** Results are many small files. Batch the pulls.
    **Seen:** one pull was 13 GB in 59,735 files; 102 pulls totalled about 570 GB. The 200 GB transfer request was too low.

## Storage

14. **Rule:** Run `bsc_quota` before the first push. A new allocation's project quota can be tiny.
    **Seen:** "Disk quota exceeded" at 287 MB of an image: 512 MB project quota, 1.95 TB scratch.
    **Fix:** working tree on scratch; quota raise requested from support.
15. **Rule:** Scratch is not backed up and is purged. Stage results to projects inside the job; pull logs promptly.
    **Seen:** a job that errored before its staging step left everything stranded on scratch. (The purge itself was
    never observed; the team's ruling was "weeks, not days".)
16. **Rule:** `flock` does not serialise across nodes on GPFS. Build shared things once, gate on a `.ready` marker.
    **Seen:** three array tasks entered a one-time venv build at once: two pips, one venv, OSError.
17. **Rule:** Every task and job writes to its own path. Shared stores race.
    **Seen:** two trainings sharing one datasets cache: one died while the other loaded identical data fine.
18. **Rule:** Two jobs that render the same config filename clobber each other.
    **Seen:** one job's edits landed in the other's config mid-flight ("no gradient_accumulation_steps key").
    **Fix:** job-unique filenames.
19. **Rule:** Keep caches off `$HOME` and set each cache variable explicitly.
    **Seen:** inside the container the hub cache resolved elsewhere, a pre-staged kernel was never found, the job died.

## Environment and software

20. **Rule:** No outbound internet on compute or login nodes. Stage dependencies, weights, kernels; force hub clients offline.
    **Seen:** the first smoke found system Python 3.9 with no numpy, pandas or scikit-learn importable.
21. **Rule:** `#!/bin/bash -l` on every batch script.
    **Seen:** a plain `#!/bin/bash` does not source the module system; `module load` failed and `set -e` killed the job.
    Three submissions lost to module-chain mistakes.
22. **Rule:** Hierarchical Python modules need their toolchain first (`module load intel mkl python/3.12.1`), then
    `unset PYTHONHOME PYTHONPATH`, or the module shadows your venv.
23. **Rule:** The container runtime is a module (`module load singularity/<ver>`), not on the default PATH.
    **Seen:** instant failure "execve(): singularity: No such file or directory".
24. **Rule:** The site's module Python can have broken stdlib extensions.
    **Seen:** `import sqlite3` fails under the Intel-built Python 3.12.1 (old libsqlite3); optuna imports it eagerly.
    **Fix:** `pysqlite3-binary` in the bundle plus a `sitecustomize.py` swap.
25. **Rule:** pip evaluates dependency environment markers against the laptop, not the target.
    **Seen:** bundling on an ARM Mac silently dropped greenlet (marker names x86_64/aarch64, not arm64); install failed on
    the cluster with "No matching distribution". A GPU library's CUDA dependency was likewise absent.
    **Fix:** name such packages explicitly; install the GPU library with `--no-deps` in the CPU venv.
26. **Rule:** Key a cached venv on the wheel's content hash, not its filename.
    **Seen:** a package pinned at 0.1.0 kept its filename across rebuilds; the reinstall was skipped forever; a 702-task
    sweep died at config load leaving 702 zero-byte files.
27. **Rule:** One OpenMP runtime per process; set `OMP_NUM_THREADS` explicitly.
    **Seen:** a duplicate OpenMP runtime in the CPU stack segfaulted.
28. **Rule:** JIT compilers inside an NGC container may not find the driver library on the cluster.
    **Seen:** `torch.compile` failed with "libcuda.so cannot found!" (driver under `/usr/local/cuda/compat/lib`).
    **Fix:** compile off by default.

## Containers

29. **Rule:** Build for the cluster's architecture, x86_64, whatever the laptop is.
    **Seen:** July 2026: an ARM image, the default on an Apple-Silicon Docker VM, would not run on the cluster.
    **Fix:** `--platform linux/amd64` forced on the builder; Rosetta enabled in the VM. Verify with `sif list` (shows
    "squashfs amd64") and the image smoke on a GPU node.
30. **Rule:** Import checks inside an emulated amd64 build can fail falsely. Only the cluster proves an image.
    **Seen:** x86 numeric libraries crashed at import (SIGILL) under emulation; the image ran fine on the cluster.
31. **Rule:** No image builds on the cluster: no fakeroot, no sudo, no internet. Build elsewhere, copy the `.sif` in.
32. **Rule:** The cluster runs containers as your uid. Interpreters under root-only paths are not executable.
    **Seen:** "exec: .../python: Permission denied", exit 126 in 13 s, caught by the image smoke.
    **Fix:** `chmod -R a+rX` on the app and venv paths in `%post`.
33. **Rule:** Never pip-install a second framework over a vendor-matched base; pin numpy to the base's version.
    **Seen:** reinstalling numpy over the base gave "RuntimeError: Numpy is not available" at `torch.from_numpy`.
34. **Rule:** Check the base image's Python against your package's requirement before building.
    **Seen:** one NGC tag shipped Python 3.10; the install aborted with "requires a different Python".
35. **Rule:** A base image can bake in a dead package-index host.
    **Seen:** `pypi.ngc.nvidia.com` was NXDOMAIN; two builds died in timeouts. **Fix:** repoint the extra index.
36. **Rule:** A killed build leaves a `.sif` that looks complete. Check the header; confirm the build wrote where the push reads.
    **Seen:** a 5.98 GB "invalid magic" corpse after a mid-write kill; separately, a build wrote into a different checkout and
    the pushed image was a week old.
37. **Rule:** On macOS the Docker VM shares only `$HOME`; long builds must be detached and kept awake.
    **Seen:** a workdir outside `$HOME` mounted empty ("no such file" at def open); one build was killed by a memory
    watchdog at "Creating SIF file"; another died because the VM was not running after a reboot.
    **Fix:** build under `$HOME`, `nohup caffeinate -i ...`.
38. **Rule:** The build tool refuses to overwrite an existing image, and says so on the LAST line.
    **Seen:** a wrapper reported exit 0 over "FATAL: build target already exists"; the stale image was pushed.
39. **Rule:** Code in an image is stale until rebuilt. A fresh sbatch on a stale image gives no error.
    **Seen:** a stale-schema image killed every GPU job at config load in about 11 s; a freshness check that only looked at
    the wheel said "no blockers" while the container was 40 minutes stale.
40. **Rule:** Images run on compute nodes only.
    **Seen:** `singularity exec` on the login node failed for want of `/scratch/tmp`.

## Submit

41. **Rule:** Pass `--cpus-per-task` on every `srun` and export `SRUN_CPUS_PER_TASK`.
    **Seen:** a rank silently received one core; the dataloader starved. Measured: inheritance from `#SBATCH` is
    unreliable even with the export.
42. **Rule:** `sbatch --export` splits on commas. Never pass a list through it.
    **Seen:** a 60-item value truncated at the first comma; the job ran one item.
43. **Rule:** With `--export=ALL`, variables left in the shell leak into the next submission.
    **Seen:** a results path exported by an earlier command sent a new sweep's output into the old folder.
44. **Rule:** Never let an empty command substitution fall through to a script default.
    **Seen:** a `$(...)` that depended on a laptop-only tool returned empty on the login node; the sbatch ran its
    hardcoded default list. Twice. **Fix:** scripts refuse to run without an explicit input.
45. **Rule:** `#SBATCH` lines cannot expand variables, and SLURM does not create log directories.
    **Fix:** absolute paths rendered into the file; `mkdir -p` the logs directory before `sbatch`.
46. **Rule:** Do not change sbatch files, images, bundles or datasets that pending or running jobs read.
    **Seen:** a code push during a running array killed 20 tasks with no log at all.
47. **Rule:** `afterok` on an array needs every task to succeed; one TIMEOUT leaves the dependent job pending forever.
    **Seen:** two tuning workers hit the wall; the chained finals died "DependencyNeverSatisfied".
    **Fix:** resubmit, resume, re-chain by hand.

## Queue and QoS

48. **Rule:** Confirm which queues the allocation has before writing scripts. GPU-only allocations reject CPU QoS names;
    CPU-only tasks can still run on GPU nodes without requesting a GPU.
    **Seen:** `bsc_queues` showed only `acc_debug / acc_ehpc / acc_interactive`; `gp_ehpc` gave "Invalid qos specification".
49. **Rule:** The per-user submission cap counts every array task, pending or running. Size each send against the
    whole queue; send in drained batches.
    **Seen:** two 360-task arrays sent together: the second rejected with `QOSMaxSubmitJobPerUserLimit`, the dependent GPU
    chain aborted behind it. Two live patches made it worse; the fix was cancel everything, redesign once, resend.
50. **Rule:** A whole-node GPU request can wait over a day; partial-node requests start in minutes.
    **Seen:** 4-GPU requests pending more than a day while two co-located GPUs were free. **Fix:** effective batch made
    invariant to GPU count; inference on 2 GPUs.
51. **Rule:** Know the QoS maximum wall (3 days on the production GPU QoS, 2 hours on debug). Shorter walls on a resume
    get better priority.

## Budget

52. **Rule:** Find out whether the allocation bills GPU-hours or core-hours before any arithmetic. It swings the usable
    budget fourfold. Here: 5,000 GPU-h = 100,000 CPU-h at 20 cores per GPU. `sacct` core-hours double-count SMT threads.
53. **Rule:** The spend is long multi-worker GPU searches, and a restart doubles it. Elapsed time bills, not wall.
    **Seen:** a 16-worker x 48 h chain ran twice; about 7,000 core-hours lost; a cancelled stale round burned about
    410 GPU-h. A 40-trial study ran 43 trials.

## Failure and recovery

54. **Rule:** Keep search state durable at a path that does not depend on the job id, so a resubmit resumes it.
    **Seen:** two 12 h tuning arms hit the wall with in-memory state and lost every trial, about 24 GPU-hours.
55. **Rule:** TIMEOUT means resubmit the same command with a wall sized from the progress. Count completed work first.
    **Seen:** a leader timed out at 2 days; a bespoke database-rebuild tool was built; the plain resume took minutes.
56. **Rule:** Size walls from measured step counts with margin. Reusing a smaller job's wall for a bigger one times out.
    **Seen:** a 12 h wall reused for 2.5x the data; a final undersized at 12 h resubmitted at 36.
57. **Rule:** Unbuffered stdout and periodic checkpoints, or a timeout leaves no log and nothing on disk.
    **Seen:** a trainer with buffered stdout timed out at 8 h with no progress log; a model with no checkpoint lost all of it.
58. **Rule:** Long fine-tunes run with `--requeue` and resume from a checkpoint whose path comes from the live config.
    **Seen:** a stale hardcoded run name made the resume load another run's checkpoints: "size mismatch lora_B".
59. **Rule:** On 64 GB GPUs a frozen bf16 base is replicated per GPU under ZeRO-2 and ZeRO-3. Quantise the base; size
    inference batches to a measured token ceiling.
    **Seen:** OOM at 54 GB per GPU on a 27B model; `device_map` OOM past batch 16.
60. **Rule:** When a submission goes wrong, cancel what is yours and redesign once.
    **Seen:** two patches on a live queue, then "can we not just kill all and start again cleanly".
61. **Rule:** A run that died at the wall printed verdicts before it died. Read the log, not the exit code.
    **Seen:** exit 124 at a 90-minute wall already showed two failures at 52%; the two-hour rerun found the same two.

## Monitoring

62. **Rule:** Assert GPU visibility and log the driver banner at job start.
    **Seen:** without `--gres`, `nvidia-smi -L` says "No devices found" and the job trains on the CPU.
63. **Rule:** A cheap smoke on the debug queue before every fleet or new image.
    **Seen:** the image smoke caught exit 126 in 13 s; a flag forwarded to torchrun failed instantly; a limit-5 run caught a
    bad bundle before 700 tasks.
64. **Rule:** A result can claim a setting that was never applied. Byte-compare a variant against the baseline.
    **Seen:** 720 of 720 outputs byte-identical to the baseline at six times the cost; a GPU variant identical to baseline
    cost about 20 GPU-hours.

## Laptop side

65. **Rule:** A laptop that slept looks like a hung process. Check the sleep log; keep the machine awake.
    **Seen:** a process "hung 17 h at 99% CPU" finished two minutes after the lid opened; a signed request expired mid-call;
    `caffeinate -i` does not stop lid-close sleep. **Fix:** `pmset -g log | grep -E "Sleep|Wake"` first; `caffeinate -dims`.
66. **Rule:** zsh does not word-split unquoted variables; bash does.
    **Seen:** a command "completed" in 0 s with exit 0 because its arguments went in as one word. Six times.
67. **Rule:** Anything under `/private/tmp` on macOS disappears on restart.
    **Seen:** a restart cleared a scratch clone with about 15 commits.
68. **Rule:** Laptop and cluster numerics differ slightly. The decision number comes from the cluster.
    **Seen:** the same fit scored 0.2936 on ARM and 0.2853 on the cluster.

## Etiquette

69. **Rule:** Never submit or run work from `/gpfs/home`. *Documented, not seen:* login nodes kill processes over 5 min of CPU.
70. **Rule:** Throttle arrays (`%K`); the throttle limits running tasks, not queued ones.
71. **Rule:** Shared large inputs live read-only in one path; separate workstreams by scratch namespace, image and job name.

## Not verified by the team (do not state as fact)

- Whether the transfer nodes have outbound internet.
- Whether `apptainer build` or `pull` works anywhere on the cluster (never attempted; stated impossible by site guidance).
- Whether the BSC VPN is needed from inside the EU (site docs say outside the EU only; the team worked from Barcelona
  without it).
- Whether a code push is safe while an array is pending (sources disagree; treat as unsafe).
