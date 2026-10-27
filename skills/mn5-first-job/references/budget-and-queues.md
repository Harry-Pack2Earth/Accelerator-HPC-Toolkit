# Budget, queues, walls

## Units first

Ask what the allocation bills: GPU-hours or core-hours. On MareNostrum 5 ACC under EuroHPC allocations the team
measured 20 cores billed per GPU, so **5,000 GPU-hours = 100,000 CPU-hours** in `bsc_acct`. Getting this wrong
swings the usable budget by four. `sacct` core-hour sums double-count SMT threads; trust `bsc_acct`. Measured on a smoke job: `--cpus-per-task=4` showed
`cpu=8,billing=8` in `sacct` (two hardware threads per core). Budget by `bsc_acct`, not by `AllocTRES`: on one full allocation `bsc_acct` reported 96.36 of 100 kCPU-h while the
`sacct` thread sum was double that, and BSC's own statement of the award was 5,000 GPU-h = 100 kCPU-h at 20 cores
per GPU. So 20 cores per GPU is the billed figure, not 40.

## Arithmetic

```
GPU-hours  = GPUs x elapsed hours x tasks
billed CPU = GPU-hours x cores per GPU            (20 here)
CPU tasks  = cores x elapsed hours x tasks / cores per GPU  (as GPU-hour equivalent)
```

`scripts/estimate_cost.sh --gpus 4 --hours 18` → 72 GPU-h, 1,440 CPU-h, 1.4% of 5,000. Elapsed time bills, not
the wall you asked for; a cancelled job still bills what it ran.

Reference points from one allocation: a 4-GPU fine-tune of a 27B model, 13 h → 52 GPU-h. A single-GPU model
training, 2 to 12 h. A 19,000-task CPU sweep at 8 cores. About 40 GPU-h per day across a three-month allocation.

## Where budgets die

- Long multi-worker GPU searches that restart. A 16-worker x 48 h chain run twice cost about 7,000 core-hours.
- Searches with in-memory state that hit the wall: every trial lost (about 24 GPU-h once).
- Variants that were never applied: 720 outputs byte-identical to the baseline at six times the cost.
- A study that over-ran its trial count (43 on a 40-trial study) because nothing stopped the workers.

Rules: durable state at a stable path; a shared stop condition across workers; byte-compare a variant against its
baseline before reading results; walls sized from measured progress with margin.

## Queues

- Debug QoS: minutes to start, 2 h max, ONE job per user at a time (`MaxSubmitPU 1`), for smokes and image checks only.
- Production QoS: 3-day max wall; shorter walls get better priority on a resume.
- Whole-node (4 GPU) requests: can wait more than a day. 1-2 GPUs: minutes. Make the job GPU-count tolerant
  (constant effective batch) and take what is offered.
- Per-user submission cap (`sacctmgr show qos <qos> format=MaxSubmitPU`): counts every array task, pending or
  running. A send that would exceed it is rejected whole, and anything chained behind it aborts.
  `scripts/submit.sh` checks this before `--go`. Send in drained batches.
- Array throttle `%K` limits running tasks, not queued ones. Use it to be a good neighbour.
- `afterok` chains across arrays are brittle; one TIMEOUT blocks the chain forever. Resubmit by hand.

## Before every production submission

1. `scripts/estimate_cost.sh` for this job.
2. `scripts/status.sh`: remaining budget, what is queued.
3. `scripts/submit.sh <dir> <file>` without `--go`: `sbatch --test-only` + cap check.
4. Show the human: cost, share of budget, wall, GPUs, what happens on TIMEOUT. Then `--go`.
