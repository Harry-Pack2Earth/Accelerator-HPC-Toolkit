#!/usr/bin/env bash
# sync_push.sh — copy files/dirs from the laptop to <PROJECTS_DIR>/<dest> through the transfer node.
# Usage: scripts/sync_push.sh <dest: subdir of PROJECTS_DIR, or an absolute path such as $IMAGES_DIR> <path> [<path> ...] [--dry-run] [--verify] [--mirror [--confirm-delete]]
# --verify is MANDATORY for images: a 13 GB image once arrived as a 172 MB stub and every job died at mount.
# Transfers always start on the laptop; the cluster cannot reach you. Interrupted transfers resume (--partial).
set -euo pipefail
source "$(dirname "$0")/_env.sh"
DEST=""; DRY=0; VERIFY=0; MIRROR=0; CONFIRM=0; PATHS=()
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; --verify) VERIFY=1 ;; --mirror) MIRROR=1 ;; --confirm-delete) CONFIRM=1 ;; *) if [[ -z "$DEST" ]]; then DEST="$a"; else PATHS+=("$a"); fi ;; esac; done
[[ -n "$DEST" && ${#PATHS[@]} -gt 0 ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
CLEAN=(); for p in "${PATHS[@]}"; do p="${p%/}"; [[ -e "$p" ]] || { echo "no such path: $p" >&2; exit 2; }; CLEAN+=("$p"); done
[[ "$DEST" = /* ]] && DEST_ABS="$DEST" || DEST_ABS="${PROJECTS_DIR}/${DEST}"
REMOTE="${CLUSTER_USER}@${TRANSFER_HOST}:${DEST_ABS}/"
PATHS=("${CLEAN[@]}")   # a trailing slash would make rsync copy a directory's CONTENTS and break the verify manifest
FLAGS=(-av --partial --human-readable --exclude .git --exclude __pycache__ --exclude .DS_Store)
[[ $DRY -eq 1 ]] && FLAGS+=(--dry-run)
# --mirror deletes remote files that no longer exist locally. Use it for DATASETS, so the remote is never the union of
# every version ever pushed (files dropped locally once survived remotely and three result sets disagreed on the count).
if [[ $MIRROR -eq 1 ]]; then
  FLAGS+=(--delete)
  # List what would be deleted BEFORE deleting anything; proceed only with --confirm-delete (the agent shows the list).
  if [[ $DRY -eq 0 ]]; then
    on_transfer mkdir -p "${DEST_ABS}"
    DEL="$(rsync "${FLAGS[@]}" --dry-run --itemize-changes "${PATHS[@]}" "${REMOTE}" | grep '^\*deleting' || true)"
    if [[ -n "$DEL" && $CONFIRM -eq 0 ]]; then
      echo "--mirror would delete these remote files:"; echo "$DEL"; echo "Re-run with --confirm-delete to proceed." >&2; exit 4
    fi
    [[ -n "$DEL" ]] && { echo "deleting on the remote:"; echo "$DEL"; }
  fi
fi
echo "rsync ${FLAGS[*]} ${PATHS[*]} ${REMOTE}"
on_transfer mkdir -p "${DEST_ABS}"
keep_awake rsync "${FLAGS[@]}" "${PATHS[@]}" "${REMOTE}"
if [[ $VERIFY -eq 1 && $DRY -eq 0 ]]; then
  MANIFEST="$(mktemp)"
  # manifest paths are relative to the DESTINATION: a pushed file lands as its basename, a pushed directory as
  # <dirname>/<contents>. A laptop-relative path like project/test.sif would never be found by the remote check.
  for p in "${PATHS[@]}"; do (cd "$(dirname "$p")" && find "$(basename "$p")" -type f -exec shasum -a 256 {} +); done > "$MANIFEST"
  rsync -q "$MANIFEST" "${CLUSTER_USER}@${TRANSFER_HOST}:${DEST_ABS}/.push_manifest.sha256"
  on_transfer "cd '${DEST_ABS}' && sha256sum -c --quiet .push_manifest.sha256 && echo VERIFY_OK"
fi
