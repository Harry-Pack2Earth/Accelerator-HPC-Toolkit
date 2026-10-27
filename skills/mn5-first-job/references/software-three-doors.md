# Software on the cluster: three doors

Nothing installs on the cluster. No internet on the nodes, no root. Everything arrives from the laptop.

| Door | For | How | Proof |
|---|---|---|---|
| 1. Site modules | stdlib Python, system tools | `module avail`, `module load` in the sbatch | smoke job |
| 2. Offline wheel bundle → venv on GPFS | CPU Python: pandas, scikit-learn, boosted trees | `scripts/build_wheels.sh` → push → `scripts/install_wheels_remote.sh` once from the login node | a 1-task array on the debug queue |
| 3. Apptainer image | anything with a GPU | `scripts/build_sif.sh` off-cluster → push `--verify` | `templates/image_smoke.sbatch` on a GPU node |

Most founders start at door 2. Go to door 3 only when a GPU is needed.

## Door 2 details

- Target the cluster's Python (`python/3.12.1` → `cp312`, `manylinux_2_28_x86_64`). The script does this on any laptop.
- pip evaluates dependency markers against the LAPTOP. On an ARM Mac a package needed only on x86_64 is silently
  skipped and the cluster install fails with "No matching distribution". Name it explicitly and re-bundle.
- Install ONCE from the login node. Never from inside array tasks: `flock` does not serialise across nodes on GPFS.
  Jobs test the `.ready` marker the installer writes last.
- `unset PYTHONHOME PYTHONPATH` after `module load`, before activating the venv.
- The module Python's `sqlite3` is broken; if a dependency imports it, add `pysqlite3-binary` and a `sitecustomize.py`
  that swaps it in.

## Door 3 details

- Base on a vendor image whose torch, CUDA and cuDNN are matched (NGC `nvcr.io/nvidia/pytorch:<dated tag>`). Pin the
  tag. Do not list torch in requirements. Pin numpy to the base's version.
- `%post`: `chmod -R a+rX` on everything you add. The cluster runs the container as your uid.
- Push with `scripts/sync_push.sh images <file.sif> --verify`. Non-negotiable: a truncated image kills every job at mount.
- Prove it with the image smoke on the debug queue. The login node cannot run images.
- After every code change: rebuild, re-push, re-smoke. A stale image runs old code with no error.

## Building the image on each kind of laptop

The cluster is x86_64. The image must be `linux/amd64`. That is the whole cross-platform story.

| Laptop | Path | Verified by the team |
|---|---|---|
| Linux x86_64 with Apptainer | `scripts/build_sif.sh --mode native` (`--fakeroot`; or `sudo`) | in progress (Ubuntu 24.04 VM, Oct 2026): no `apptainer` apt package on 24.04; install the `.deb` from https://github.com/apptainer/apptainer/releases (1.5.5 worked) |
| macOS, Apple Silicon | colima (`--vm-type vz --cpu 4 --memory 8`, qemu binfmt or Rosetta), then `scripts/build_sif.sh --mode docker` (apptainer inside a privileged amd64 container) | **yes on macOS 26** (every production image, July to September 2026). **FAILS on macOS 27.0.1** (checked 27 Oct 2026: same profile, same builder digest, even a 3-line alpine def dies at "Failed to spawn stage 1" when `%post` starts). Until understood: build on a Linux VM or WSL2 and copy the `.sif` back |
| macOS, Intel | same docker mode, no emulation | no (same code path, native amd64; the macOS 27 failure may or may not apply) |
| Windows x86_64 | Ubuntu under WSL2, Apptainer `.deb` there, native mode | **yes** (Server 2022 + WSL2 Ubuntu 24.04, Oct 2026): preflight and smoke identical to Linux; `--fakeroot` fails in WSL2 (binfmt_misc already mounted by Windows interop), `sudo apptainer build` works, the script falls back to it |
| Windows on ARM | docker mode under emulation, or a cloud x86_64 VM | no |
| Any | a cheap x86_64 Linux cloud VM with Apptainer: build there, `rsync` from there to the transfer node | no |

Apple-Silicon specifics the team hit:
- The colima profile that built every production image had `rosetta: false` (qemu binfmt); the script's own comments
  claimed Rosetta. Check `~/.colima/<profile>/colima.yaml`, not comments.
- Rosetta off → `exec format error` at build start. colima: `colima start --vm-type vz --vz-rosetta`. Docker Desktop:
  Settings → General → "Use Rosetta for x86_64/amd64 emulation on Apple Silicon".
- Import checks in `%post` crash under emulation (SIGILL in x86 numeric libraries). The template makes them non-fatal.
  The cluster smoke is the proof.
- The Docker VM shares only `$HOME`. Build from a folder under `$HOME`.
- A 10-20 GB base pull plus the build takes long enough for the laptop to sleep: `nohup caffeinate -i scripts/build_sif.sh ...`.
- Verify: `apptainer sif list <file>` (or the same inside the builder container) shows a squashfs partition for amd64.
- Some CUDA extensions (ones compiled at install time) cannot be built on a Mac at all; use a base image that ships
  them, or build on a Linux GPU machine.

Windows notes (exercised on a Windows Server 2022 machine with WSL2, Oct 2026): do everything in the WSL2 Ubuntu terminal,
including `ssh` and `rsync`; stock Windows has no rsync. Keep the working folder on the Linux side of WSL2
(`~/...`), not under `/mnt/c`, for speed and file permissions.
