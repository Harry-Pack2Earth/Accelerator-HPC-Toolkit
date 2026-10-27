# shellcheck shell=bash
# sourced by the other scripts: loads cluster.env and defines ssh/rsync helpers
ENV_FILE="${HPC_ENV:-cluster.env}"
[[ -f "$ENV_FILE" ]] || { echo "missing $ENV_FILE: run scripts/preflight.sh first" >&2; exit 2; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
# accept-new: a never-seen host key is accepted (a fresh laptop knows none); a CHANGED key is still refused.
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o ServerAliveInterval=60)
# the remote login shell prints module banners on stderr for every command; drop those lines, keep real errors
quiet_banners() { grep -vE '^(load |Set INTEL|Loads storage|unload )' >&2 || true; }
on_login()    { ssh "${SSH_OPTS[@]}" "${CLUSTER_USER}@${LOGIN_HOST}" "$@" 2> >(quiet_banners); }
on_transfer() { ssh "${SSH_OPTS[@]}" "${CLUSTER_USER}@${TRANSFER_HOST}" "$@" 2> >(quiet_banners); }
# caffeinate -i stops IDLE sleep during a long transfer. It does NOT stop lid-close sleep: tell the human to keep
# the lid open and the laptop on power for a multi-GB push or pull.
keep_awake() { if command -v caffeinate >/dev/null 2>&1; then caffeinate -i "$@"; else "$@"; fi; }
