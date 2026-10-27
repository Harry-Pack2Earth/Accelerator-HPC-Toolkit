#!/usr/bin/env bash
# install_wheels.sh — laptop side: push a wheel bundle and build (or rebuild) the venv on the cluster, in one step.
# Usage: scripts/install_wheels.sh <wheels dir from build_wheels.sh>
# Reads cluster.env: WHEELS_DIR, VENV_DIR, PYTHON_MODULE. Runs install_wheels_remote.sh ONCE on the login node
# (never inside jobs: flock does not serialise across nodes on GPFS). Jobs then test VENV_DIR/.ready.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_env.sh"
WHEELS="${1:-}"; [[ -d "$WHEELS" && -f "$WHEELS/.bundle" ]] || { echo "usage: $0 <wheels dir made by build_wheels.sh>" >&2; exit 2; }
[[ -n "${PYTHON_MODULE:-}" ]] || { echo "PYTHON_MODULE missing from cluster.env: re-run scripts/preflight.sh" >&2; exit 2; }
PY_VER="${PYTHON_MODULE#python/}"; PY_VER="${PY_VER%.*}"   # python/3.12.1 -> 3.12
echo "bundle: $WHEELS  ->  ${WHEELS_DIR}   venv: ${VENV_DIR}   module: ${PYTHON_MODULE} (bundle must be cp${PY_VER//./} wheels)"
"$HERE/sync_push.sh" "${WHEELS_DIR}" "$WHEELS/" "$HERE/install_wheels_remote.sh" --mirror --confirm-delete
echo "== building the venv on ${LOGIN_HOST} =="
on_login "bash '${WHEELS_DIR}/install_wheels_remote.sh' '${WHEELS_DIR}' '${VENV_DIR}' '${PYTHON_MODULE}'"
echo "venv ready at ${VENV_DIR}. Render templates/cpu_array.sbatch and submit with scripts/submit.sh."
