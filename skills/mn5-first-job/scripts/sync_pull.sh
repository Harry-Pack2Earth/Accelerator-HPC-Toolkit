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
FLAGS=(-av --partial --human-readable); [[ $DRY -eq 1 ]] && FLAGS+=(--dry-run)
echo "rsync ${FLAGS[*]} ${CLUSTER_USER}@${TRANSFER_HOST}:${SRC}/ ${OUT}/"
keep_awake rsync "${FLAGS[@]}" "${CLUSTER_USER}@${TRANSFER_HOST}:${SRC}/" "${OUT}/"
echo "pulled into ${OUT}"
