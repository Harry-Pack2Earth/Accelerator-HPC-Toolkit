#!/usr/bin/env bash
# install_wheels_remote.sh — runs ON A LOGIN NODE (scripts/install_wheels.sh calls it): venv on GPFS from an offline bundle.
# Usage: bash install_wheels_remote.sh <bundle dir on the cluster> <VENV_DIR> <bundle hash> <python module>
# Builds VENV_DIR/<hash>/ once (idempotent: a finished venv is kept) and points VENV_DIR/current at it. A venv is
# never modified in place: a stale wheel with an unchanged filename once left a 702-task sweep running old code, and
# running jobs must keep the venv they started with. Nothing touches the network. One writer at a time (flock on
# the login node; this script never runs inside jobs).
set -euo pipefail
WHEELS="${1:?bundle dir}"; VENV_ROOT="${2:?VENV_DIR}"; HASH="${3:?bundle hash}"; PY_MODULE="${4:?python module, e.g. python/3.12.1}"
VENV="${VENV_ROOT}/${HASH}"
[[ -f "${WHEELS}/requirements.txt" ]] || { echo "no requirements.txt in ${WHEELS}" >&2; exit 2; }
module purge
# Some Python modules are hierarchical: they only load after their compiler/MKL parents. Try plain, then with parents.
module load "$PY_MODULE" 2>/dev/null || module load intel mkl "$PY_MODULE"
unset PYTHONHOME PYTHONPATH   # the module exports these; they shadow a venv
mkdir -p "$VENV_ROOT"
exec 9>"${VENV_ROOT}/.venv.lock"; flock 9
if [[ -f "${VENV}/.ready" ]]; then
  echo "venv ${HASH} already built; pointing current at it"
else
  rm -rf "$VENV"   # only ever a half-built venv of this same hash
  python -m venv "$VENV"
  "${VENV}/bin/python" -m pip install --no-index --find-links "$WHEELS" -r "${WHEELS}/requirements.txt"
  "${VENV}/bin/python" -c "import sys; print('venv ok', sys.version.split()[0], sys.executable)"
  echo "$PY_MODULE" > "${VENV}/.python_module"
  touch "${VENV}/.ready"        # written LAST
fi
ln -s "$HASH" "${VENV_ROOT}/current.tmp.$$" && mv -Tf "${VENV_ROOT}/current.tmp.$$" "${VENV_ROOT}/current"   # atomic switch: no instant without a current
echo "current -> $(readlink "${VENV_ROOT}/current")"
