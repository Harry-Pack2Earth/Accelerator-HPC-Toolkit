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
| `preflight.sh` against a real account | macOS | pending | | |
| `run_smoke.sh` end to end on MN5 (debug queue) | macOS | pending | | |
| `build_wheels.sh` + `install_wheels_remote.sh` + 1-task `cpu_array` | macOS → MN5 | pending | | |
| `build_sif.sh --mode docker` (Rosetta) + `image_smoke.sbatch` | macOS Apple Silicon → MN5 | pending (method used in production by the authors, scripts not yet re-run) | | |
| `build_sif.sh --mode native` | Linux x86_64 VM | pending | | |
| whole procedure in WSL2 | Windows x86_64 cloud VM | pending | | |
| cold run by a person who has never used MN5, with an agent | fresh user account | pending | | |

Unverified site facts are listed at the end of `skills/mn5-first-job/references/lessons.md`.
