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
# push the bundle CONTENTS (a directory argument would land as WHEELS_DIR/<dirname>/...); --mirror drops stale wheels
"$HERE/sync_push.sh" "${WHEELS_DIR}" "$WHEELS"/*.whl "$WHEELS/requirements.txt" "$WHEELS/.bundle" "$HERE/install_wheels_remote.sh" --mirror --confirm-delete
echo "== building the venv on ${LOGIN_HOST} =="
# the venv is the one sanctioned login-node task (a pip install of wheels: seconds, no network); never while jobs that use it are queued
QUEUED="$(on_login "squeue -r -h -u '${CLUSTER_USER}' | wc -l" | tr -d ' ')"
[[ "${QUEUED:-0}" -eq 0 ]] || { echo "You have ${QUEUED} job(s) queued or running. A venv rebuild under a running job breaks it; wait for the queue to drain." >&2; exit 4; }
on_login "bash -l '${WHEELS_DIR}/install_wheels_remote.sh' '${WHEELS_DIR}' '${VENV_DIR}' '${PYTHON_MODULE}'"
echo "venv ready at ${VENV_DIR}. Render templates/cpu_array.sbatch and submit with scripts/submit.sh."
