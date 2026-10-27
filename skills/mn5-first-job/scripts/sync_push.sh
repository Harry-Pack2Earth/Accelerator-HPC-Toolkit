#!/usr/bin/env bash
# sync_push.sh — copy files/dirs from the laptop to <PROJECTS_DIR>/<dest> through the transfer node.
# Usage: scripts/sync_push.sh <dest: subdir of PROJECTS_DIR, or an absolute path such as $BIG_FILES_DIR/images> <path> [<path> ...] [--dry-run] [--verify] [--mirror]
# --verify is MANDATORY for images: a 13 GB image once arrived as a 172 MB stub and every job died at mount.
# Transfers always start on the laptop; the cluster cannot reach you. Interrupted transfers resume (--partial).
set -euo pipefail
source "$(dirname "$0")/_env.sh"
DEST=""; DRY=0; VERIFY=0; MIRROR=0; PATHS=()
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; --verify) VERIFY=1 ;; --mirror) MIRROR=1 ;; *) if [[ -z "$DEST" ]]; then DEST="$a"; else PATHS+=("$a"); fi ;; esac; done
[[ -n "$DEST" && ${#PATHS[@]} -gt 0 ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
for p in "${PATHS[@]}"; do [[ -e "$p" ]] || { echo "no such path: $p" >&2; exit 2; }; done
[[ "$DEST" = /* ]] && DEST_ABS="$DEST" || DEST_ABS="${PROJECTS_DIR}/${DEST}"
REMOTE="${CLUSTER_USER}@${TRANSFER_HOST}:${DEST_ABS}/"
FLAGS=(-av --partial --human-readable --exclude .git --exclude __pycache__ --exclude .DS_Store)
[[ $DRY -eq 1 ]] && FLAGS+=(--dry-run)
# --mirror deletes remote files that no longer exist locally. Use it for DATASETS, so the remote is never the union of
# every version ever pushed (files dropped locally once survived remotely and three result sets disagreed on the count).
[[ $MIRROR -eq 1 ]] && FLAGS+=(--delete)
echo "rsync ${FLAGS[*]} ${PATHS[*]} ${REMOTE}"
on_transfer mkdir -p "${DEST_ABS}"
keep_awake rsync "${FLAGS[@]}" "${PATHS[@]}" "${REMOTE}"
if [[ $VERIFY -eq 1 && $DRY -eq 0 ]]; then
  MANIFEST="$(mktemp)"
  for p in "${PATHS[@]}"; do find "$p" -type f -exec shasum -a 256 {} + ; done > "$MANIFEST"
  rsync -q "$MANIFEST" "${CLUSTER_USER}@${TRANSFER_HOST}:${DEST_ABS}/.push_manifest.sha256"
  on_transfer "cd '${DEST_ABS}' && sha256sum -c --quiet .push_manifest.sha256 && echo VERIFY_OK"
fi
