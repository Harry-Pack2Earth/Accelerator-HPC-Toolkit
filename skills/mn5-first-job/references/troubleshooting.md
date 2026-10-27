# Troubleshooting: symptom → cause → fix

Read the `.err` log first (`scripts/status.sh <job id>` lists it). Then find the symptom here.

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied (publickey,...)` on ssh | key not on the cluster | upload the public key in the accounts portal (upload replaces the file: include every key) |
| ssh hangs then times out | network path blocked | connect to the BSC VPN (needed from outside the EU) |
| script "succeeded" but nothing arrived on the cluster | password prompt killed the unattended ssh; exit code lied | key-based login; verify on the remote side (`ls`, `sha256sum -c`) |
| `Invalid qos specification` | QoS name from the wrong partition (`gp_*` on a GPU-only allocation) | use the QoS names `bsc_queues` prints |
| `QOSMaxSubmitJobPerUserLimit` | per-user cap; counts every array task pending or running | smaller batches; wait for the queue to drain; `squeue -r -u <user> \| wc -l` |
| job pending for a day, reason `Resources`/`Priority` | whole-node (4-GPU) request | request 1-2 GPUs; make the job GPU-count tolerant |
| job dies instantly, no log file at all | log directory does not exist; SLURM will not create it | `mkdir -p` the logs dir before `sbatch`; absolute paths in `#SBATCH --output` |
| `module: command not found` | batch script not a login shell | `#!/bin/bash -l` |
| `python/3.12.1` module not found | hierarchical module | `module load intel mkl python/3.12.1` |
| venv ignored, wrong Python runs | module exported `PYTHONHOME`/`PYTHONPATH` | `unset PYTHONHOME PYTHONPATH` before activating |
| `execve(): singularity: No such file or directory` | runtime is a module | `module load singularity/<version>` |
| `singularity exec` fails on the login node, `/scratch/tmp` | images run on compute nodes only | test with the image smoke job |
| `exec: .../python: Permission denied` (exit 126, seconds) | files in the image not readable/executable by your uid | `chmod -R a+rX` in `%post`, rebuild |
| bad superblock / cannot mount image | truncated transfer | `sync_push.sh ... --verify`; compare sizes |
| `invalid magic` on an image that looks complete | build killed mid-write | rebuild with `--force`; check `sif list` before pushing |
| GPU job runs on CPU, `No devices found` | no `--gres=gpu:N` | add `--gres`; assert `torch.cuda.is_available()` at start |
| `RuntimeError: Numpy is not available` | numpy reinstalled over the base image's | pin numpy to the base version; never install a second torch |
| `requires a different Python: 3.10` at build | base image too old for the package | newer base tag (check its Python before building) |
| build dies in index timeouts | dead package-index host baked into the base | repoint `PIP_EXTRA_INDEX_URL` |
| `exec format error` at image build on a Mac | amd64 emulation off | enable Rosetta (colima `--vz-rosetta` / Docker Desktop setting) |
| SIGILL during `%post` import check on a Mac | emulation artifact, not a broken image | ignore (template is non-fatal); prove on the cluster |
| `no such file` at def open in docker mode on a Mac | workdir outside `$HOME`, VM mounts it empty | build from under `$HOME` |
| `FATAL: build target already exists` (last line) | tool refuses to overwrite | `--force` |
| every GPU job dies at config load in ~10 s after a code change | stale image | rebuild, re-push, re-smoke |
| `python3: No module named pip` on the laptop | stock Ubuntu/Debian/WSL2 Python has no pip | `sudo apt-get install -y python3-pip` (macOS: `python3 -m ensurepip --user`) |
| `No matching distribution for <pkg>` during offline install | bundle built on ARM dropped an x86-only dependency | name the package explicitly in requirements; re-bundle |
| `import sqlite3` fails under module Python | broken stdlib extension in the Intel build | `pysqlite3-binary` + `sitecustomize.py` swap |
| two array tasks corrupt one venv | cross-node race; `flock` does not work on GPFS | install once from the login node; jobs test `.ready` |
| dataloader starved, one core used | `srun` did not inherit `--cpus-per-task` | pass it on `srun` and export `SRUN_CPUS_PER_TASK` |
| job ran one item of a list | `--export` splits on commas | render the list into the file or ship it as a file |
| output landed in last week's folder | leftover exported variable with `--export=ALL` | set every variable explicitly per submission |
| job ran a default you did not ask for | empty command substitution fell through | scripts must refuse to run without explicit input |
| 20 tasks died with no log mid-array | files they read were replaced while pending | never touch inputs of queued jobs |
| dependent job `DependencyNeverSatisfied` | one task of the array failed or timed out | resubmit the failed task; re-chain by hand |
| batch step `ExitCode 13:0`, no srun step, empty error log | a `cmd \| head` pipe under `set -o pipefail` (SIGPIPE) | no pipes into head/grep; query the tool directly |
| `Failed to spawn stage 1` building in Docker on a Mac | apptainer's starter cannot spawn inside Docker on macOS 27 / current colima | `--mode docker`: Docker builds, apptainer converts from the daemon |
| `TIMEOUT` | wall too short | count progress; resubmit the SAME job with a wall sized from it; checkpoint next time |
| timed out with no progress in the log | buffered stdout | `PYTHONUNBUFFERED=1`; log per step |
| OOM on a 64 GB GPU with a model that "fits in 80 GB" | these H100s have 64 GB | quantise the base; smaller batch; measured token ceiling |
| `libcuda.so cannot found!` from `torch.compile` | JIT cannot see the compat driver path in the container | compile off |
| `Disk quota exceeded` on the first push | tiny project quota on a new allocation | check `bsc_quota`; use scratch for the tree; ask support |
| laptop process "hung" overnight | the laptop slept | `pmset -g log \| grep -E "Sleep\|Wake"`; `caffeinate -dims`; lid open |
| laptop disk full after pulls | re-derivable artifacts pulled into every timestamped dir | `--exclude` them; batch pulls |
| rsync exit 23 | a missing optional source | normal; check what did arrive |
| `rsync: mkdir failed` | remote parent missing | `ssh ... mkdir -p` first (`sync_push.sh` does) |
| rsync flag "unknown option" on a Mac | openrsync / rsync 2.6.9 | `brew install rsync` |
| same fit, slightly different score on laptop vs cluster | machine numerics | decide on the cluster's number |
