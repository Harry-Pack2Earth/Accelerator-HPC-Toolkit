#!/usr/bin/env bash
# install_wheels_remote.sh — runs ON A LOGIN NODE (scripts/install_wheels.sh calls it): venv on GPFS from the offline bundle.
# Usage: bash install_wheels_remote.sh <wheels dir on the cluster> <venv dir> <python module>
# Run it ONCE from the login node, never from inside array tasks: flock does not serialise across nodes on GPFS,
# and three tasks installing into one venv at once corrupt it. Idempotent: if the bundle's content hash matches the
# recorded one the venv is kept; if it differs the venv is rebuilt (a reinstall over an old venv keeps stale wheels
# whose filename did not change, a 702-task sweep once died on that). Nothing touches the network.
set -euo pipefail
WHEELS="${1:?wheels dir}"; VENV="${2:?venv dir}"; PY_MODULE="${3:?python module, e.g. python/3.12.1}"
[[ -f "${WHEELS}/requirements.txt" ]] || { echo "no requirements.txt in ${WHEELS}" >&2; exit 2; }
module purge
# Some Python modules are hierarchical: they only load after their compiler/MKL parents. Try plain, then with parents.
module load "$PY_MODULE" 2>/dev/null || module load intel mkl "$PY_MODULE"
unset PYTHONHOME PYTHONPATH   # the module exports these; they shadow a venv
mkdir -p "$(dirname "$VENV")"
exec 9>"$(dirname "$VENV")/.venv.lock"; flock 9
NEW_SUM="$(cd "$WHEELS" && sha256sum ./*.whl requirements.txt | sha256sum | cut -c1-16)"
OLD_SUM="$(cat "${VENV}/.wheels.sha256" 2>/dev/null || true)"
if [[ -f "${VENV}/.ready" && "$NEW_SUM" == "$OLD_SUM" ]]; then echo "venv up to date (bundle ${NEW_SUM}); nothing to do"; exit 0; fi
if [[ -d "$VENV" ]]; then
  # only remove a venv this script made (marker present); never an arbitrary directory
  [[ -f "${VENV}/.wheels.sha256" || -f "${VENV}/.ready" ]] || { echo "${VENV} exists and was not made by this script; choose another VENV_DIR" >&2; exit 2; }
  echo "bundle changed (${OLD_SUM:-none} -> ${NEW_SUM}); rebuilding the venv"; rm -rf "$VENV"
fi
python -m venv "$VENV"
"${VENV}/bin/python" -m pip install --no-index --find-links "$WHEELS" -r "${WHEELS}/requirements.txt"
"${VENV}/bin/python" -c "import sys; print('venv ok', sys.version.split()[0], sys.executable)"
echo "$PY_MODULE" > "${VENV}/.python_module"
echo "$NEW_SUM" > "${VENV}/.wheels.sha256"
touch "${VENV}/.ready"        # written LAST: jobs test this file, not the lock
