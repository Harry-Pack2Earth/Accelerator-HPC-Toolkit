# BSC MareNostrum 5: site facts

Each fact is labelled. **measured** = observed on the machine by the team. **documented** = BSC user guide
(https://www.bsc.es/supportkc/docs/MareNostrum5/intro, read it in a browser; it blocks automated fetches) or BSC
support mail. **unverified** = plausible, not confirmed. When a fact here disagrees with what `preflight.sh`
discovers, the machine wins.

## Hosts

| Role | Hostnames | Label |
|---|---|---|
| CPU partition (GPP) login | `glogin1.bsc.es` .. `glogin4` | documented, measured |
| GPU partition (ACC) login | `alogin1.bsc.es` .. `alogin4` | documented, measured |
| Data transfer | `transfer1.bsc.es` .. `transfer4` (equivalent) | documented, measured |
| Accounts portal (SSH keys) | https://hpcaccounts.bsc.es/ | documented (support mail, Oct 2026) |

- Submit GPU jobs from an ACC login node. A GPU-only allocation has only `acc_*` queues. **measured**
- All transfers start on the laptop and target a transfer node. The cluster cannot push to you. **documented**
- VPN: site docs say needed from outside the EU. The team never needed it from Spain. **unverified beyond that**
- Password login is being phased out by end of 2026; keys go through the portal and each upload replaces
  `authorized_keys`. **documented (support mail 14 Oct 2026)**

## Storage (GPFS, same paths on every node)

| Path | Purpose | Notes |
|---|---|---|
| `/gpfs/home/<project>/<user>` | dotfiles | 80 GB; never run from here (documented) |
| `/gpfs/projects/<project>/<user>` | durable: code, images, venvs, results | quota varies: 1 TB on one allocation, 512 MB on another (measured) |
| `/gpfs/scratch/<project>/<user>` | job I/O, logs | not backed up, purged; 1 to 2 TB (measured) |

Commands: `bsc_project list`, `bsc_queues`, `bsc_quota`, `bsc_acct`, plus standard `squeue`, `sacct`,
`sacctmgr show qos <name> format=Name,MaxWall,MaxSubmitPU`. **measured**

## Nodes

- ACC node: 4 x NVIDIA H100 with **64 GB** each (measured; not the 80 GB of other H100 systems), 80 CPU cores.
  Billing: 20 cores per GPU, so 5,000 GPU-h = 100,000 CPU-h. **measured**
- Driver seen on ACC nodes: 595.71.05 (September 2026), 595.91.07 / CUDA 13.2 (27 October 2026), so CUDA 12.x and 13.x
  runtimes run under `--nv`. **measured**
- Compute and login nodes: no outbound internet, no fakeroot, no sudo. **measured**
- Architecture x86_64 (`uname -m`). Images and wheels must be built for `linux/amd64`. **measured**
- Container runtime: `module load singularity/4.1.5` (version at the time; `module avail singularity`). **measured**
- Module Python: `python/3.12.1`, hierarchical under `intel` + `mkl`; its sqlite3 is broken. **measured**
- System Python on nodes without modules: 3.9, no scientific packages. **measured (July 2026)**

## Queues (QoS)

| QoS | Use | Limits (measured, Sep 2026) |
|---|---|---|
| `acc_debug` | smoke, image checks | max wall 2 h |
| `acc_ehpc` | production on EuroHPC GPU allocations | max wall 3 days; `MaxSubmitPU` 366, counting every array task |
| `acc_interactive` | interactive sessions | |
| `gp_debug`, `gp_ehpc` | the CPU-partition equivalents | rejected on a GPU-only allocation |

Every `sbatch` needs `--account` (`-A`) and `--qos` (`-q`). Queue time for a whole 4-GPU node: over a day at times;
two GPUs: minutes. **measured**

## Programmes that give startups access

- BSC AI Factory accelerator (https://bsc-aifactory.eu/accelerator/): 5,000 GPU-hours on MN5 per startup. **documented**
- EuroHPC AI Factories Playground Access: allocations of 5,000 GPU-h for 3 months, with a final report due within 3
  months of the end. **documented**
