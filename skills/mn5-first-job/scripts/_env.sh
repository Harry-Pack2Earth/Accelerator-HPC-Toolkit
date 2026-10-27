# shellcheck shell=bash
# sourced by the other scripts: loads cluster.env and defines ssh/rsync helpers
ENV_FILE="${HPC_ENV:-cluster.env}"
[[ -f "$ENV_FILE" ]] || { echo "missing $ENV_FILE: run scripts/preflight.sh first" >&2; exit 2; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=60)
on_login()    { ssh "${SSH_OPTS[@]}" "${CLUSTER_USER}@${LOGIN_HOST}" "$@"; }
on_transfer() { ssh "${SSH_OPTS[@]}" "${CLUSTER_USER}@${TRANSFER_HOST}" "$@"; }
# long transfers from a laptop die when the lid closes; on macOS keep it awake for the duration
keep_awake() { if command -v caffeinate >/dev/null 2>&1; then caffeinate -i "$@"; else "$@"; fi; }
