#!/usr/bin/env bash
# sync_pull.sh — copy a results directory from the cluster to ./pulled/<timestamp>/ on the laptop.
# Usage: scripts/sync_pull.sh <remote dir relative to PROJECTS_DIR, or absolute> [--dry-run]
set -euo pipefail
source "$(dirname "$0")/_env.sh"
SRC="${1:-}"; DRY=0; [[ "${2:-}" == "--dry-run" || "${1:-}" == "--dry-run" ]] && DRY=1
[[ -n "$SRC" && "$SRC" != "--dry-run" ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[[ "$SRC" = /* ]] || SRC="${PROJECTS_DIR}/${SRC}"
OUT="pulled/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"
# -rlt not -a: no attempt to set owner/group/perms on the laptop side (fails in sandboxed folders and is pointless here)
FLAGS=(-rltv --partial --human-readable); [[ $DRY -eq 1 ]] && FLAGS+=(--dry-run)
echo "rsync ${FLAGS[*]} ${CLUSTER_USER}@${TRANSFER_HOST}:${SRC}/ ${OUT}/"
rc=0; keep_awake rsync "${FLAGS[@]}" "${CLUSTER_USER}@${TRANSFER_HOST}:${SRC}/" "${OUT}/" || rc=$?
# exit 23 = "some files/attrs were not transferred": normal for a missing optional source or an attribute the laptop
# refuses. It is only a failure when nothing arrived.
if [[ $rc -eq 23 && -n "$(ls -A "$OUT")" ]]; then echo "rsync exit 23: some files or attributes were not transferred (its messages are above). Files that did arrive are in $OUT; check the list before trusting a partial pull."; rc=0; fi
if [[ $rc -ne 0 ]]; then rmdir "$OUT" 2>/dev/null || true; echo "pull failed (rsync exit $rc)" >&2; exit "$rc"; fi
echo "pulled into ${OUT}"
