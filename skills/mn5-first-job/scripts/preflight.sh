#!/usr/bin/env bash
# preflight.sh — run on YOUR LAPTOP before anything else.
#
# Checks the laptop side (ssh, rsync, key-based login), then discovers the cluster
# side (project, queues, quota, budget, architecture) and writes cluster.env, which
# every other script reads. Nothing is hardcoded about your allocation.
#
# Usage:
#   scripts/preflight.sh --user <cluster username> [--project <code>] [--login glogin1.bsc.es] [--transfer transfer1.bsc.es] [--out cluster.env] [--dry-run]
#   --project is required when the account has more than one allocation (the script stops and lists them).
#
# Exit codes: 0 ok, 2 laptop-side problem (fix and re-run), 3 cluster-side problem.
set -uo pipefail

USER_NAME=""; LOGIN_HOST="glogin1.bsc.es"; TRANSFER_HOST="transfer1.bsc.es"; OUT="cluster.env"; DRY=0; PROJECT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_NAME="$2"; shift 2 ;;
    --login) LOGIN_HOST="$2"; shift 2 ;;
    --transfer) TRANSFER_HOST="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --project) PROJECT_ARG="$2"; shift 2 ;;
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
  # stdout only: the remote login shell prints module banners on stderr for every command. ANSI colours and
  # terminal hyperlinks are stripped so the output can be parsed.
  ssh "${SSH_OPTS[@]}" "${USER_NAME}@${host}" "$@" 2>>preflight.stderr.log | strip_ansi
}
ESC="$(printf '\033')"
strip_ansi() { sed -E "s/${ESC}\[[0-9;]*[A-Za-z]//g; s/${ESC}\]8;;[^${ESC}]*${ESC}\\\\//g"; }
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=12)
# try_hosts <base>: base like glogin1.bsc.es; tries glogin1..4 and sets FOUND_HOST to the first that answers.
# Returns 1 if none did. Sets LAST_ERR to key | hostkey | net. Runs in THIS shell (not $(...)), so those survive.
# Login nodes do go down (one refused connections and another timed out on the same morning the rest answered).
try_hosts() {
  local base="$1" prefix num domain i host out
  FOUND_HOST=""
  prefix="${base%%[0-9]*}"; num="${base#"$prefix"}"; num="${num%%.*}"; domain="${base#*.}"
  for i in "$num" 1 2 3 4; do
    host="${prefix}${i}.${domain}"; [[ " $TRIED " == *" $host "* ]] && continue; TRIED="$TRIED $host"
    if out="$(ssh "${SSH_OPTS[@]}" "${USER_NAME}@${host}" hostname 2>&1)"; then FOUND_HOST="$host"; return 0; fi
    case "$out" in
      *"Permission denied"*) echo "KEY_REFUSED ${host}: ${out}" >&2; LAST_ERR=key ;;
      *"Host key verification failed"*|*"REMOTE HOST IDENTIFICATION HAS CHANGED"*) echo "HOST_KEY_CHANGED ${host}: the key in ~/.ssh/known_hosts differs from the server's; a human must check with BSC before removing the line" >&2; LAST_ERR=hostkey ;;
      *) echo "UNREACHABLE ${host}: ${out}" >&2; LAST_ERR=net ;;
    esac
  done
  return 1
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
TRIED=""; LAST_ERR=""
if [[ $DRY -eq 1 ]]; then
  echo "[dry-run] ssh -o BatchMode=yes ${USER_NAME}@${LOGIN_HOST} hostname"; echo "[dry-run] ssh -o BatchMode=yes ${USER_NAME}@${TRANSFER_HOST} hostname"
else
  LOGIN_BASE="$LOGIN_HOST"; LOGIN_HOST=""
  if try_hosts "$LOGIN_BASE"; then LOGIN_HOST="$FOUND_HOST"
  else
    # the other login family: GPU-only allocations live on alogin*, CPU ones on glogin*
    case "$LOGIN_BASE" in glogin*) ALT="alogin1.${LOGIN_BASE#*.}" ;; *) ALT="glogin1.${LOGIN_BASE#*.}" ;; esac
    if try_hosts "$ALT"; then LOGIN_HOST="$FOUND_HOST"; fi
  fi
  TRANSFER_BASE="$TRANSFER_HOST"; TRANSFER_HOST=""
  if try_hosts "$TRANSFER_BASE"; then TRANSFER_HOST="$FOUND_HOST"; fi
  if [[ -z "$LOGIN_HOST" || -z "$TRANSFER_HOST" ]]; then
    case "$LAST_ERR" in
      key) cat >&2 <<'MSG'
Key login refused. Fix on the laptop, then re-run preflight:
  1. Make a key if you have none:   ssh-keygen -t ed25519
  2. Upload ~/.ssh/id_ed25519.pub in the BSC accounts portal (SSH KEYS -> ADD NEW SSH KEY).
     The upload REPLACES the authorized_keys file on the cluster: include every key you still want.
  3. If the key HAS a passphrase, scripts cannot type it: run `ssh-add ~/.ssh/id_ed25519` once per login session
     (the same "Permission denied" appears when the agent is not running).
  4. Test by hand:  ssh -o BatchMode=yes <user>@<host> hostname
MSG
      ;;
      net) echo "No login or transfer node answered (refused / timed out). From outside the EU connect to the BSC VPN first; otherwise wait and retry, or check https://www.bsc.es/supportkc for maintenance." >&2 ;;
      *) echo "See the messages above." >&2 ;;
    esac
    exit 2
  fi
  echo "LOGIN_OK login=${LOGIN_HOST} transfer=${TRANSFER_HOST}"
fi

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
  PROJECT="<project>"; QOS_DEBUG="<debug qos>"; QOS_PROD="<production qos>"; KIND="unknown"; QOS_MAX_WALL=""; PROJECTS_QUOTA_GB=""
else
  # bsc_queues prints "SLURM ACCOUNT: <code>" and one line per QoS: "<name> [(D)] <max time> <max proc> <description>"
  ALL_PROJECTS="$(echo "$QUEUES_RAW" | grep -oE 'SLURM ACCOUNT: *[A-Za-z0-9_]+' | awk '{print $NF}' | sort -u | tr '\n' ' ')"
  N_PROJECTS="$(echo "$ALL_PROJECTS" | wc -w | tr -d ' ')"
  if [[ -n "$PROJECT_ARG" ]]; then
    [[ " $ALL_PROJECTS " == *" $PROJECT_ARG "* ]] || { echo "ERROR: --project $PROJECT_ARG is not one of: $ALL_PROJECTS" >&2; exit 3; }
    PROJECT="$PROJECT_ARG"
  elif [[ "$N_PROJECTS" -gt 1 ]]; then
    echo "This account has several allocations: ${ALL_PROJECTS}. Jobs bill the one you pick. Ask the human which, then re-run with --project <code>." >&2; exit 3
  else
    PROJECT="$(echo "$ALL_PROJECTS" | awk '{print $1}')"
  fi
  [[ -n "$PROJECT" ]] || PROJECT="$(echo "$PROJECT_RAW" | grep -oE '\b[a-z]{2,6}[0-9]{2,4}\b' | head -1)"
  if echo "$QUEUES_RAW" | grep -qE '^\s*acc_'; then KIND="acc"; else KIND="gp"; fi
  QOS_DEBUG="$(echo "$QUEUES_RAW" | grep -oE "${KIND}_debug" | head -1)"
  QOS_PROD="$(echo "$QUEUES_RAW" | grep -E "^\s*${KIND}_[a-z]+ +\(D\)" | awk '{print $1}' | head -1)"
  [[ -n "$QOS_PROD" ]] || QOS_PROD="$(echo "$QUEUES_RAW" | grep -oE "^\s*${KIND}_[a-z]+" | tr -d ' ' | grep -v -E 'debug|interactive' | head -1)"
  QOS_MAX_WALL="$(echo "$QUEUES_RAW" | grep -E "^\s*${QOS_PROD}( +\(D\))? +[0-9]" | sed -E 's/\(D\)//' | awk '{print $2}' | head -1)"
  # gpfs_projects quota line: "gpfs_projects GRP <usage> <unit> <quota> <unit> <limit> <unit> ..."
  PROJECTS_QUOTA_GB="$(echo "$QUOTA_RAW" | grep gpfs_projects | head -1 | awk '{q=$5; u=$6; if (u=="MB") q=q/1024; if (u=="TB") q=q*1024; printf "%.1f", q}')"
fi
if [[ -z "$PROJECT" ]]; then echo "Could not read a project code from bsc_project; paste the output above to the human." >&2; exit 3; fi
echo "project=$PROJECT kind=$KIND qos_debug=${QOS_DEBUG:-?} qos_prod=${QOS_PROD:-?}"
if [[ "$KIND" == "acc" && "$LOGIN_HOST" == glogin* && $DRY -eq 0 ]]; then
  echo "NOTE: this allocation is GPU-only (acc_* queues); jobs must be submitted from an ACC login node. Switching."
  try_hosts "alogin1.${LOGIN_HOST#*.}" || { echo "no ACC login node answered" >&2; exit 3; }
  LOGIN_HOST="$FOUND_HOST"; echo "login=${LOGIN_HOST}"
fi
ACCT_RAW="$(run_remote "$LOGIN_HOST" bsc_acct)"; echo "bsc_acct:"; echo "$ACCT_RAW"
QOS_LIMITS="$(run_remote "$LOGIN_HOST" "sacctmgr -n -P show qos '${QOS_PROD}','${QOS_DEBUG}' format=Name,MaxWall,MaxSubmitPU,MaxJobsPU 2>/dev/null" | grep -E '^[a-z]')"
echo "qos limits (Name|MaxWall|MaxSubmitPU|MaxJobsPU):"; echo "${QOS_LIMITS:-not readable}"
QOS_MAX_SUBMIT="$(echo "$QOS_LIMITS" | grep "^${QOS_PROD}|" | cut -d'|' -f3)"
QOS_DEBUG_MAX_SUBMIT="$(echo "$QOS_LIMITS" | grep "^${QOS_DEBUG}|" | cut -d'|' -f3)"
QOS_DEBUG_MAX_WALL="$(echo "$QOS_LIMITS" | grep "^${QOS_DEBUG}|" | cut -d'|' -f2)"
[[ -n "$QOS_MAX_WALL" ]] || QOS_MAX_WALL="$(echo "$QOS_LIMITS" | grep "^${QOS_PROD}|" | cut -d'|' -f2)"
echo "NOTE: MaxSubmitPU counts EVERY array task, pending or running. Size each submission against the whole queue."
echo "NOTE: the debug QoS has its own, small cap (${QOS_DEBUG_MAX_SUBMIT:-?}): smoke with one task there; arrays go to ${QOS_PROD}."
BIG_FILES_DIR="/gpfs/projects/${PROJECT}/${USER_NAME}/big"; RESULTS_DIR="/gpfs/projects/${PROJECT}/${USER_NAME}/results"
if [[ -n "$PROJECTS_QUOTA_GB" ]] && awk "BEGIN{exit !($PROJECTS_QUOTA_GB < 20)}"; then
  BIG_FILES_DIR="/gpfs/scratch/${PROJECT}/${USER_NAME}/big"; RESULTS_DIR="/gpfs/scratch/${PROJECT}/${USER_NAME}/results"
  echo "NOTE: gpfs_projects quota is only ${PROJECTS_QUOTA_GB} GB (one real allocation had 512 MB). Images, wheels, venv AND results"
  echo "      go under scratch (${BIG_FILES_DIR%/big}), which is not backed up: pull results promptly. Ask BSC support to raise the quota."
fi
# the newest python module on the system; the venv is built with it and every CPU job loads the same one
PYTHON_MODULE="$(echo "$PY_MODULES" | tr ' ' '\n' | grep -E '^python/' | sort -t/ -k2,2V | tail -1)"

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
QOS_DEBUG_MAX_WALL="${QOS_DEBUG_MAX_WALL}"
QOS_DEBUG_MAX_SUBMIT="${QOS_DEBUG_MAX_SUBMIT}"
REMOTE_ARCH="${REMOTE_ARCH}"
LAPTOP_OS="${OS}"
LAPTOP_ARCH="${ARCH}"
PROJECTS_DIR="/gpfs/projects/${PROJECT}/${USER_NAME}"
SCRATCH_DIR="/gpfs/scratch/${PROJECT}/${USER_NAME}"
BIG_FILES_DIR="${BIG_FILES_DIR}"
IMAGES_DIR="${BIG_FILES_DIR}/images"
WHEELS_DIR="${BIG_FILES_DIR}/wheels"
VENV_DIR="${BIG_FILES_DIR}/venv"
RESULTS_DIR="${RESULTS_DIR}"
PROJECTS_QUOTA_GB="${PROJECTS_QUOTA_GB}"
PYTHON_MODULE="${PYTHON_MODULE}"
PYTHON_MODULES="${PY_MODULES}"
CONTAINER_MODULES="${SING_MODULES}"
# cores billed per GPU on the accelerated partition (check against bsc_acct after your first GPU job)
CORES_PER_GPU=20
ENV
cat "$OUT"
echo
echo "Preflight done. Next: the smoke job (scripts/run_smoke.sh)."
