#!/usr/bin/env bash
# install_wheels.sh — laptop side: push a wheel bundle and build its venv on the cluster, in one step.
# Usage: scripts/install_wheels.sh <wheels dir from build_wheels.sh>
# Reads cluster.env: WHEELS_DIR, VENV_DIR, PYTHON_MODULE. Each bundle goes to WHEELS_DIR/<hash>/ and gets its own venv
# at VENV_DIR/<hash>/; VENV_DIR/current then points at it. Running jobs keep using the venv they started with, so
# this is safe while jobs are queued. Runs install_wheels_remote.sh ONCE on the login node (never inside jobs:
# flock does not serialise across nodes on GPFS). Jobs test VENV_DIR/current/.ready.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_env.sh"
WHEELS="${1:-}"; WHEELS="${WHEELS%/}"; [[ -d "$WHEELS" && -f "$WHEELS/.bundle" ]] || { echo "usage: $0 <wheels dir made by build_wheels.sh>" >&2; exit 2; }
[[ -n "${PYTHON_MODULE:-}" ]] || { echo "PYTHON_MODULE missing from cluster.env: re-run scripts/preflight.sh" >&2; exit 2; }
PY_VER="${PYTHON_MODULE#python/}"; PY_VER="${PY_VER%.*}"   # python/3.12.1 -> 3.12
HASH="$( (cd "$WHEELS" && ls -1 ./*.whl requirements.txt | LC_ALL=C sort | xargs shasum -a 256) | shasum -a 256 | cut -c1-12)"
echo "bundle: $WHEELS (hash $HASH)  ->  ${WHEELS_DIR}/${HASH}   venv: ${VENV_DIR}/${HASH}   module: ${PYTHON_MODULE} (bundle must be cp${PY_VER//./} wheels)"
"$HERE/sync_push.sh" "${WHEELS_DIR}/${HASH}" "$WHEELS"/*.whl "$WHEELS/requirements.txt" "$WHEELS/.bundle" "$HERE/install_wheels_remote.sh"
echo "== building the venv on ${LOGIN_HOST} =="
on_login "bash -l '${WHEELS_DIR}/${HASH}/install_wheels_remote.sh' '${WHEELS_DIR}/${HASH}' '${VENV_DIR}' '${HASH}' '${PYTHON_MODULE}'"
echo "venv ready: ${VENV_DIR}/current -> ${HASH}. Render templates/cpu_array.sbatch and submit with scripts/submit.sh."
echo "Old bundles and venvs stay under ${WHEELS_DIR} and ${VENV_DIR} (a few hundred MB each); remove them by hand when no job uses them."
