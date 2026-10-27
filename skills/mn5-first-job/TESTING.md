# Testing status

Claims in the skill are only as good as this table. A row is **verified** when the command was run on that
machine and the artifact checked, not when it "should work".

| What | Machine | Status | Date | Evidence |
|---|---|---|---|---|
| `bash -n`, shellcheck on all scripts | macOS 27 (Apple Silicon) | verified | 2026-10-27 | shellcheck clean |
| `preflight.sh --dry-run` | macOS 27 | verified | 2026-10-27 | writes a sourceable cluster.env |
| `render.sh` on all six templates, unfilled-token refusal | macOS 27 | verified | 2026-10-27 | all rendered; missing ARGS refused |
| `run_smoke.sh --dry-run` | macOS 27 | verified | 2026-10-27 | |
| `estimate_cost.sh` GPU and CPU forms | macOS 27 | verified | 2026-10-27 | 4x18h → 72 GPU-h, 1,440 CPU-h |
| `smoke_job.py` locally | macOS 27 | verified | 2026-10-27 | SMOKE_OK, JSON written |
| `preflight.sh` against a real account | macOS 27 | verified | 2026-10-27 | found project, acc partition, QoS limits 3-00:00:00 / cap 366, 0.5 GB projects quota → big files on scratch, switched to alogin1; fixed on the way: accept-new host keys, try next login node, strip ANSI, stdout-only capture |
| `run_smoke.sh` end to end on MN5 (debug queue) | macOS 27, stock `/bin/bash` 3.2, tree dee12a1 | verified | 2026-10-27 | job 48134778 SMOKE_VERIFIED on the post-review tree (earlier: 48129465) |
| (earlier run of the same, pre-review tree) | macOS 27 | superseded | 2026-10-27 | job 48129465 COMPLETED in 6 s on as01r1b31; artifact pulled: x86_64, system Python 3.9.21, no numpy, no GPU; fixed on the way: pull tolerates rsync exit 23, `-rlt` not `-a`, banner filter |
| door 2: `build_wheels.sh` → `install_wheels.sh` (twice: build, then "up to date") → 1-task `cpu_array` on the debug QoS → pull | macOS 27, stock bash 3.2 → MN5 | verified | 2026-10-27 | job 48134204_0 `TASK_OK numpy 2.5.4 pandas 3.1.0` from the offline bundle on python/3.12.1; a 2-task array on the production QoS (job 48134216) queued with an estimated start the next morning and ran about an hour later: both tasks COMPLETED in 12 s. Run on the pre-round-2 design; the per-hash venv design is re-run in the final chain below |
| `build_sif.sh --mode docker-def` (apptainer in a privileged container, the July-Sept recipe) | macOS 27.0.1, colima | FAILS | 2026-10-27 | "Failed to spawn stage 1" at %post, same colima profile and builder digest as the September builds; also fails for a native arm64 def |
| `build_sif.sh --mode docker` (Docker builds, apptainer converts from the daemon) + push `--verify` + `image_smoke.sbatch` | macOS 27.0.1, colima | running | 2026-10-27 | tiny image verified (Squashfs amd64); real image built, push + H100 smoke in progress |
| `preflight.sh` + `run_smoke.sh` | Ubuntu 24.04 x86_64 (EC2 t3.large), agent-forwarded key | verified | 2026-10-27 | job 48129580 COMPLETED, SMOKE_VERIFIED |
| `preflight.sh` + `run_smoke.sh` on the FINAL tree (37cc7a6) | fresh Ubuntu 24.04 x86_64 (EC2 c6i.2xlarge), nothing preinstalled | verified | 2026-10-27 | job 48135572 SMOKE_VERIFIED; budget line and job-named pull folder in the output |
| door 2 on the FINAL tree (980b089): pip check → `build_wheels.sh` → `install_wheels.sh` twice (build, then "already built") → `cpu_array` with the venv hash pinned at render time, `ARGS` + manifest line → pull | same fresh Ubuntu VM | verified | 2026-10-27 | stock Ubuntu has no pip (the script says how to install it); job 48137019 `TASK_OK ['--mode','test','alpha','1'] numpy 2.5.4 pandas 3.1.0` from `VENV_DIR/d185170f2183` |
| `build_sif.sh --mode native` + push `--verify` + `image_smoke.sbatch` | Ubuntu 24.04 x86_64 VM (t3.large) | verified | 2026-10-27 | apptainer 1.5.5 (.deb; no apt package on 24.04); 13.1 GB image; push 6 min 20 s, VERIFY_OK; job 48132883 `IMAGE_OK x86_64 torch 2.6.0 cu12.8 NVIDIA H100 65247 MiB`; fixed on the way: verify manifest paths, stale job id, SIGPIPE in the template, newest module version |
| `preflight.sh` + `run_smoke.sh` in WSL2 | Windows Server 2022 (m5zn.metal) + WSL2 Ubuntu 24.04, normal user | verified | 2026-10-27 | job 48130637 SMOKE_VERIFIED; preflight switched itself to alogin1 |
| `build_sif.sh --mode native` in WSL2 + push `--verify` + `image_smoke.sbatch` | same | verified | 2026-10-27 | `--fakeroot` fails (binfmt_misc already mounted by WSL interop), sudo fallback built the 13 GB image in 9 min 17 s; VERIFY_OK (sha c47fe66e…); job 48133027 `IMAGE_OK x86_64 torch 2.6.0 cu12.8 NVIDIA H100 65247 MiB` |
| cold run: a fresh agent with ONLY the skill folder (no repo, no session context), told "use the skill, my username is X", stock `/bin/bash` 3.2 | macOS 27, tree 9e33f70 | verified | 2026-10-27 | preflight → run_smoke → SMOKE_VERIFIED (job 48134908) with no human input; its 16 usability findings were folded into SKILL.md and the scripts afterwards (see git history) |

Unverified site facts are listed at the end of `references/lessons.md`.
