#!/usr/bin/env bash
# install_wheels_remote.sh — run ON A LOGIN NODE: make a venv on GPFS projects from the offline bundle.
# Usage (from the laptop): scripts/sync_push.sh wheels wheels/ scripts/install_wheels_remote.sh
#        then:            ssh <user>@<login> 'bash <PROJECTS_DIR>/wheels/install_wheels_remote.sh <PROJECTS_DIR> python/3.12.1'
# Run it ONCE from the login node, never from inside array tasks: flock does not serialise across nodes on GPFS,
# and three tasks installing into one venv at once corrupt it. Idempotent. Nothing touches the network.
set -euo pipefail
PROJECTS_DIR="${1:?projects dir}"; PY_MODULE="${2:?python module, e.g. python/3.12.1}"
WHEELS="$(cd "$(dirname "$0")" && pwd)"
VENV="${PROJECTS_DIR}/venv"
module purge
# Some Python modules are hierarchical: they only load after their compiler/MKL parents. Try plain, then with parents.
module load "$PY_MODULE" 2>/dev/null || module load intel mkl "$PY_MODULE"
unset PYTHONHOME PYTHONPATH   # the module exports these; they shadow a venv
exec 9>"${PROJECTS_DIR}/.venv.lock"; flock 9
if [[ ! -x "${VENV}/bin/python" ]]; then python -m venv "$VENV"; fi
"${VENV}/bin/python" -m pip install --no-index --find-links "$WHEELS" -r "${WHEELS}/requirements.txt"
"${VENV}/bin/python" -c "import sys; print('venv ok', sys.version.split()[0], sys.executable)"
sha256sum "${WHEELS}"/*.whl > "${VENV}/.wheels.sha256"
touch "${VENV}/.ready"        # written LAST: jobs test this file, not the lock (flock does not serialise across nodes on GPFS)
