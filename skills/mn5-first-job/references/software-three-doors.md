# Software on the cluster: three doors

Nothing installs on the cluster. No internet on the nodes, no root. Everything arrives from the laptop.

| Door | For | How | Proof |
|---|---|---|---|
| 1. Site modules | stdlib Python, system tools | `module avail`, `module load` in the sbatch | smoke job |
| 2. Offline wheel bundle → venv on GPFS | CPU Python: pandas, scikit-learn, boosted trees | `scripts/build_wheels.sh` on the laptop → `scripts/install_wheels.sh <bundle>` (pushes, builds the venv once on the login node) | a 1-task `cpu_array` (LAST=0) on the debug queue (it allows one job per user); the first multi-task run goes to the production QoS |
| 3. Apptainer image | anything with a GPU | `scripts/build_sif.sh` off-cluster → push `--verify` | `templates/image_smoke.sbatch` on a GPU node |

Most founders start at door 2. Go to door 3 only when a GPU is needed. Verification status of each door: `TESTING.md` in the skill folder.

## Door 2 details

- Target the cluster's Python (`python/3.12.1` → `cp312`, `manylinux_2_28_x86_64`). The script does this on any laptop.
- pip evaluates dependency markers against the LAPTOP. On an ARM Mac a package needed only on x86_64 is silently
  skipped and the cluster install fails with "No matching distribution". Name it explicitly and re-bundle.
- `install_wheels.sh` installs ONCE from the login node. Never from inside array tasks: `flock` does not serialise
  across nodes on GPFS. Each bundle gets its own folder and venv named by its content hash; `install_wheels.sh` saves the hash in
  `./.venv_hash` and `render.sh` pins it into the job, so every task of an array uses the same venv and a later
  install never changes a queued or running job. Jobs test the `.ready` marker the installer writes last and load the Python module recorded in the venv.
- `unset PYTHONHOME PYTHONPATH` after `module load`, before activating the venv.
- The module Python's `sqlite3` is broken; if a dependency imports it, add `pysqlite3-binary` and a `sitecustomize.py`
  that swaps it in.

## Door 3 details

- Base on a vendor image whose torch, CUDA and cuDNN are matched (NGC `nvcr.io/nvidia/pytorch:<dated tag>`). Pin the
  tag. Do not list torch in requirements. Pin numpy to the base's version.
- `%post`: `chmod -R a+rX` on everything you add. The cluster runs the container as your uid.
- Push with `scripts/sync_push.sh IMAGES_DIR <file.sif> --verify` (the literal name; the script resolves it from cluster.env). Non-negotiable: a truncated image kills every job at mount.
- Prove it with the image smoke on the debug queue. The login node cannot run images.
- After every code change: rebuild, re-push, re-smoke. A stale image runs old code with no error.

## Building the image on each kind of laptop

The cluster is x86_64. The image must be `linux/amd64`. That is the whole cross-platform story.

| Laptop | Path | Notes (status: TESTING.md) |
|---|---|---|
| Linux x86_64 with Apptainer | `scripts/build_sif.sh --mode native` (`--fakeroot`, then `sudo -n`; if sudo needs a password the script prints the command for the human) | Ubuntu 24.04 has no `apptainer` apt package: install the `.deb` from https://github.com/apptainer/apptainer/releases |
| macOS, Apple Silicon | `scripts/build_sif.sh --mode docker`: Docker Desktop or colima builds the image from the Dockerfile for linux/amd64 (Rosetta or qemu), apptainer in a container converts it from the daemon | The older `--mode docker-def` (apptainer itself in a privileged container running `%post`) built every image of the authors on macOS 26 and fails on macOS 27 at "Failed to spawn stage 1" |
| macOS, Intel | same docker mode, no emulation | same code path, native amd64 |
| Windows x86_64 | Ubuntu under WSL2, Apptainer `.deb` there, native mode | `--fakeroot` fails in WSL2 (binfmt_misc already mounted by Windows interop); the script falls back to `sudo` |
| Windows on ARM | docker mode under emulation, or a cloud x86_64 VM | |
| Any | a cheap x86_64 Linux cloud VM with Apptainer: build there, `rsync` from there to the transfer node | a 2-vCPU VM takes about 40 min to compress a 20 GB rootfs; 8 vCPUs is comfortable |

Apple-Silicon specifics the team hit:
- The colima profile that built every production image had `rosetta: false` (qemu binfmt); the script's own comments
  claimed Rosetta. Check `~/.colima/<profile>/colima.yaml`, not comments.
- Rosetta off → `exec format error` at build start. colima: `colima start --vm-type vz --vz-rosetta`. Docker Desktop:
  Settings → General → "Use Rosetta for x86_64/amd64 emulation on Apple Silicon".
- Import checks in `%post` crash under emulation (SIGILL in x86 numeric libraries). The template makes them non-fatal.
  The cluster smoke is the proof.
- The Docker VM shares only `$HOME`. Build from a folder under `$HOME`.
- Give the Docker VM 4+ CPUs and 8 GB for the conversion (Docker Desktop: Settings > Resources; colima:
  `colima start --cpu 4 --memory 8`): on a 2-CPU, 2 GB VM a 13 GB image took about 2.5 hours to convert.
- The conversion unpacks the whole rootfs (about twice the image size) in a temp dir. The script binds
  `~/.apptainer-cache/tmp` for it; inside the builder container it would land on the VM's small root disk
  ("no space left on device" at 13 GB on colima's 19 GB root).
- A 10-20 GB base pull plus the build takes long enough for the laptop to sleep: `nohup caffeinate -i scripts/build_sif.sh ...`.
- Verify: `apptainer sif list <file>` (or the same inside the builder container) shows a squashfs partition for amd64.
- Some CUDA extensions (ones compiled at install time) cannot be built on a Mac at all; use a base image that ships
  them, or build on a Linux GPU machine.

Windows notes: do everything in the WSL2 Ubuntu terminal,
including `ssh` and `rsync`; stock Windows has no rsync. Keep the working folder on the Linux side of WSL2
(`~/...`), not under `/mnt/c`, for speed and file permissions.
