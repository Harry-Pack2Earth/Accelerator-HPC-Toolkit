#!/usr/bin/env bash
# preflight.sh — run on YOUR LAPTOP before anything else.
#
# Checks the laptop side (ssh, rsync, key-based login), then discovers the cluster
# side (project, queues, quota, budget, architecture) and writes cluster.env, which
# every other script reads. Nothing is hardcoded about your allocation.
#
# Usage:
#   scripts/preflight.sh --user <cluster username> [--login glogin1.bsc.es] [--transfer transfer1.bsc.es] [--out cluster.env] [--dry-run]
#
# Exit codes: 0 ok, 2 laptop-side problem (fix and re-run), 3 cluster-side problem.
set -uo pipefail

USER_NAME=""; LOGIN_HOST="glogin1.bsc.es"; TRANSFER_HOST="transfer1.bsc.es"; OUT="cluster.env"; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_NAME="$2"; shift 2 ;;
    --login) LOGIN_HOST="$2"; shift 2 ;;
    --transfer) TRANSFER_HOST="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$USER_NAME" ]] || { echo "ERROR: --user <cluster username> is required (it is in your BSC welcome email)" >&2; exit 2; }

say() { printf '\n== %s ==\n' "$*"; }
run_remote() {  # run_remote <host> <command...>
  local host="$1"; shift
  if [[ $DRY -eq 1 ]]; then echo "[dry-run] ssh ${USER_NAME}@${host} -- $*" >&2; echo "dry-run"; return 0; fi
  ssh -o BatchMode=yes -o ConnectTimeout=15 "${USER_NAME}@${host}" "$@" 2>&1
}

say "1. laptop tools"
OS="$(uname -s)"; ARCH="$(uname -m)"
echo "os=$OS arch=$ARCH"
for t in ssh rsync; do
  if command -v "$t" >/dev/null 2>&1; then echo "$t: $(command -v "$t")"; else echo "MISSING: $t" >&2; MISSING=1; fi
done
if [[ "${MISSING:-0}" -eq 1 ]]; then
  echo "On Windows: open an Ubuntu (WSL2) terminal and run this from there; stock Windows has ssh but no rsync." >&2
  exit 2
fi
RSYNC_BANNER="$(rsync --version 2>&1 | head -1)"
echo "rsync: $RSYNC_BANNER"
case "$RSYNC_BANNER" in
  *openrsync*) echo "NOTE: this is Apple's openrsync, not rsync. Flags differ (no --info=progress2, partial -R support). Install GNU rsync: brew install rsync" ;;
  *"version 2."*) echo "NOTE: rsync 2.x is from 2006. Install a current one: brew install rsync" ;;
esac
if [[ "$ARCH" != "x86_64" ]]; then
  echo "NOTE: your laptop is $ARCH. The cluster is x86_64. Containers and wheel bundles must be built for linux/amd64 (see references/software-three-doors.md)."
fi

say "2. key-based login (no password prompts, so scripts can run unattended)"
for host in "$LOGIN_HOST" "$TRANSFER_HOST"; do
  if [[ $DRY -eq 1 ]]; then echo "[dry-run] ssh -o BatchMode=yes ${USER_NAME}@${host} hostname"; continue; fi
  if out="$(ssh -o BatchMode=yes -o ConnectTimeout=15 "${USER_NAME}@${host}" hostname 2>&1)"; then
    echo "LOGIN_OK ${host} -> ${out}"
  else
    echo "LOGIN_FAILED ${host}: ${out}" >&2
    cat >&2 <<'MSG'
Key login failed. Fix on the laptop, then re-run preflight:
  1. Make a key if you have none:   ssh-keygen -t ed25519
  2. Upload ~/.ssh/id_ed25519.pub in the BSC accounts portal (SSH KEYS -> ADD NEW SSH KEY).
     The upload REPLACES the authorized_keys file on the cluster: include every key you still want.
  3. If the host is unreachable at all (timeout), connect to the BSC VPN first.
  4. Test by hand:  ssh -o BatchMode=yes <user>@<host> hostname
MSG
    exit 2
  fi
done

say "3. cluster discovery"
PROJECT_RAW="$(run_remote "$LOGIN_HOST" bsc_project list)"; echo "bsc_project list:"; echo "$PROJECT_RAW"
QUEUES_RAW="$(run_remote "$LOGIN_HOST" bsc_queues)";      echo "bsc_queues:";      echo "$QUEUES_RAW"
QUOTA_RAW="$(run_remote "$LOGIN_HOST" bsc_quota)";        echo "bsc_quota:";       echo "$QUOTA_RAW"
REMOTE_ARCH="$(run_remote "$LOGIN_HOST" uname -m | tail -1)";       echo "remote arch: $REMOTE_ARCH"
PY_MODULES="$(run_remote "$LOGIN_HOST" 'module avail python 2>&1 | grep -oE "python/[0-9.]+" | sort -u | tr "\n" " "')"
SING_MODULES="$(run_remote "$LOGIN_HOST" 'module avail singularity apptainer 2>&1 | grep -oE "(singularity|apptainer)/[0-9.]+" | sort -u | tr "\n" " "')"
echo "python modules: ${PY_MODULES:-none seen}"
echo "container modules: ${SING_MODULES:-none seen}"

if [[ $DRY -eq 1 ]]; then
  PROJECT="<project>"; QOS_DEBUG="<debug qos>"; QOS_PROD="<production qos>"; KIND="unknown"
else
  PROJECT="$(echo "$PROJECT_RAW" | grep -oE '\b(ehpc|bsc|ucm|upc|ub|uab)[a-z]*[0-9]+\b' | head -1)"
  if echo "$QUEUES_RAW" | grep -q 'acc_'; then KIND="acc"; else KIND="gp"; fi
  QOS_DEBUG="$(echo "$QUEUES_RAW" | grep -oE "${KIND}_debug" | head -1)"
  QOS_PROD="$(echo "$QUEUES_RAW"  | grep -oE "${KIND}_[a-z]+" | grep -v -E 'debug|interactive' | head -1)"
fi
if [[ -z "$PROJECT" ]]; then echo "Could not read a project code from bsc_project; paste the output above to the human." >&2; exit 3; fi
echo "project=$PROJECT kind=$KIND qos_debug=${QOS_DEBUG:-?} qos_prod=${QOS_PROD:-?}"
if [[ "$KIND" == "acc" && "$LOGIN_HOST" == glogin* ]]; then
  echo "NOTE: this allocation is GPU-only (acc_* queues). GPU jobs must be submitted from an ACC login node (alogin1.bsc.es); re-run with --login alogin1.bsc.es."
fi
ACCT_RAW="$(run_remote "$LOGIN_HOST" bsc_acct)"; echo "bsc_acct:"; echo "$ACCT_RAW"
QOS_LIMITS="$(run_remote "$LOGIN_HOST" "sacctmgr -n -P show qos '${QOS_PROD}' format=Name,MaxWall,MaxSubmitPU,MaxJobsPU 2>/dev/null")"
echo "qos limits (Name|MaxWall|MaxSubmitPU|MaxJobsPU): ${QOS_LIMITS:-not readable}"
QOS_MAX_WALL="$(echo "$QOS_LIMITS" | cut -d'|' -f2)"; QOS_MAX_SUBMIT="$(echo "$QOS_LIMITS" | cut -d'|' -f3)"
echo "NOTE: MaxSubmitPU counts EVERY array task, pending or running. Size each submission against the whole queue."
echo "NOTE: if gpfs_projects quota above is tiny (one allocation had 512 MB), keep the working tree on scratch and ask support to raise it."

say "4. writing $OUT"
cat > "$OUT" <<ENV
# written by preflight.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ); re-run preflight to refresh
CLUSTER_USER="${USER_NAME}"
LOGIN_HOST="${LOGIN_HOST}"
TRANSFER_HOST="${TRANSFER_HOST}"
PROJECT="${PROJECT}"
PARTITION_KIND="${KIND}"
QOS_DEBUG="${QOS_DEBUG}"
QOS_PROD="${QOS_PROD}"
QOS_MAX_WALL="${QOS_MAX_WALL}"
QOS_MAX_SUBMIT="${QOS_MAX_SUBMIT}"
REMOTE_ARCH="${REMOTE_ARCH}"
LAPTOP_OS="${OS}"
LAPTOP_ARCH="${ARCH}"
PROJECTS_DIR="/gpfs/projects/${PROJECT}/${USER_NAME}"
SCRATCH_DIR="/gpfs/scratch/${PROJECT}/${USER_NAME}"
PYTHON_MODULES="${PY_MODULES}"
CONTAINER_MODULES="${SING_MODULES}"
# cores billed per GPU on the accelerated partition (check against bsc_acct after your first GPU job)
CORES_PER_GPU=20
ENV
cat "$OUT"
echo
echo "Preflight done. Next: the smoke job (scripts/run_smoke.sh)."
