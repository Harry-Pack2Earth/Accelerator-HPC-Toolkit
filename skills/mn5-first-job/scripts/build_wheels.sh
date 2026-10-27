#!/usr/bin/env bash
# build_wheels.sh — download an OFFLINE wheel bundle for the cluster's Python (CPU work, no container).
# Usage: scripts/build_wheels.sh --requirements <requirements.txt> [--python 3.12] [--out wheels]
# --python must match the cluster module the venv will use (cluster.env PYTHON_MODULE, e.g. python/3.12.1 -> 3.12).
# Nodes have no internet, so `pip install` cannot run there. This downloads x86_64 manylinux wheels on the
# laptop for the cluster's Python; scripts/install_wheels_remote.sh installs them into a venv on GPFS.
# Whatever your laptop is (ARM Mac included), pip downloads for the TARGET platform given here.
#
# Known trap: pip evaluates dependency environment markers against the LAPTOP, not the target. A package
# that is only required on x86_64 (greenlet behind sqlalchemy was one) is silently skipped when bundling
# on an ARM laptop and the install then fails on the cluster with "No matching distribution". Fix: name
# the package explicitly in requirements.txt and re-bundle.
set -euo pipefail
REQ=""; PY="3.12"; OUT="wheels"
while [[ $# -gt 0 ]]; do case "$1" in
  --requirements) REQ="$2"; shift 2 ;; --python) PY="$2"; shift 2 ;; --out) OUT="$2"; shift 2 ;;
  *) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac; done
[[ -n "$REQ" && -f "$REQ" ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
ABI="cp${PY//./}"
# Never wipe a directory we did not make: only an absent dir, or one holding a previous bundle (.bundle marker), is removed.
if [[ -e "$OUT" && ! -f "$OUT/.bundle" ]]; then echo "ERROR: $OUT exists and is not a wheel bundle made by this script; choose another --out" >&2; exit 2; fi
rm -rf "$OUT"; mkdir -p "$OUT"; : > "$OUT/.bundle"
python3 -m pip download \
  --only-binary=:all: \
  --python-version "$PY" --implementation cp --abi "$ABI" \
  --platform manylinux_2_28_x86_64 --platform manylinux2014_x86_64 \
  -r "$REQ" -d "$OUT"
cp "$REQ" "$OUT/requirements.txt"
echo "bundle: $OUT ($(ls "$OUT"/*.whl | wc -l | tr -d ' ') wheels, $(du -sh "$OUT" | cut -f1))"
echo "Next: scripts/install_wheels.sh $OUT    (pushes the bundle and builds the venv on the cluster)"
