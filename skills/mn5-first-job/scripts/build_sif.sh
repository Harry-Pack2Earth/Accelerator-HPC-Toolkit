#!/usr/bin/env bash
# build_sif.sh — build a linux/amd64 Apptainer image from a .def file, on whatever machine this is.
# Usage: scripts/build_sif.sh --def <file.def> --out <image.sif> [--force] [--mode native|docker]
#
# The cluster is x86_64 (linux/amd64). The image must be too, whatever your laptop is.
#   Linux x86_64 / WSL2 with apptainer installed  -> native build (--fakeroot)
#   macOS, or any machine with Docker but no apptainer -> apptainer inside a privileged Docker container,
#        forced to --platform linux/amd64. On Apple Silicon that is emulation: enable Rosetta
#        (Docker Desktop: Settings > General > "Use Rosetta for x86_64/amd64 emulation"; colima: --vz-rosetta).
#        A build that dies with "exec format error" means the emulation is not on.
# Expect the first build to pull a 10-20 GB base image. Build in a terminal that will stay awake.
set -euo pipefail
DEF=""; OUT=""; FORCE=0; MODE="auto"
APPTAINER_IMAGE="${APPTAINER_IMAGE:-kaczmarj/apptainer:latest}"
while [[ $# -gt 0 ]]; do case "$1" in
  --def) DEF="$2"; shift 2 ;; --out) OUT="$2"; shift 2 ;; --force) FORCE=1; shift ;; --mode) MODE="$2"; shift 2 ;;
  *) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac; done
[[ -n "$DEF" && -n "$OUT" ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[[ -f "$DEF" ]] || { echo "no such def file: $DEF" >&2; exit 2; }
# apptainer refuses to overwrite an existing image, and says so only on the LAST line of a long build log.
# Decide now, not after twenty minutes.
if [[ -e "$OUT" && $FORCE -eq 0 ]]; then
  echo "ERROR: $OUT exists (built $(date -r "$OUT" '+%F %H:%M' 2>/dev/null || echo '?')). Re-run with --force to rebuild." >&2
  echo "       Code changes only reach the cluster through a rebuilt + re-pushed image." >&2; exit 1
fi
FLAGS=(); [[ $FORCE -eq 1 ]] && FLAGS+=(--force)
if [[ "$MODE" == "auto" ]]; then
  if command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1; then MODE=native
  elif command -v docker >/dev/null 2>&1; then MODE=docker
  else
    echo "Neither apptainer/singularity nor docker found." >&2
    echo "  Linux/WSL2: install apptainer (https://apptainer.org/docs/admin/main/installation.html)" >&2
    echo "  macOS:      install Docker Desktop or colima, then re-run (docker mode)" >&2
    echo "  Windows:    run this inside an Ubuntu (WSL2) terminal" >&2; exit 2
  fi
fi
if [[ "$MODE" == "native" ]]; then
  BIN="$(command -v apptainer || command -v singularity)"
  [[ "$(uname -m)" == "x86_64" ]] || { echo "ERROR: native build on $(uname -m) would produce a non-x86_64 image. Use --mode docker (emulated) or an x86_64 Linux machine." >&2; exit 2; }
  echo "== native build with $BIN (--fakeroot) =="
  if ! "$BIN" build --fakeroot "${FLAGS[@]}" "$OUT" "$DEF" 2> >(tee /tmp/build_sif.err >&2); then
    # Two known failures of --fakeroot: no subuid mapping for the user, and WSL2, where apptainer tries to mount
    # binfmt_misc that Windows interop already mounted ("failed to mount binfmt_misc filesystem: invalid argument").
    # Both are fixed by building as real root, which every Linux/WSL user with sudo can do. Verified Oct 2026.
    if command -v sudo >/dev/null 2>&1; then
      echo "fakeroot build failed ($(grep -m1 -oE 'FATAL.*' /tmp/build_sif.err || echo see above)); retrying with sudo" >&2
      sudo "$BIN" build "${FLAGS[@]}" "$OUT" "$DEF" && sudo chown "$(id -u):$(id -g)" "$OUT"
    else
      echo "fakeroot build failed and no sudo: ask the admin to add you to /etc/subuid, or build on another machine" >&2; exit 1
    fi
  fi
else
  docker info >/dev/null 2>&1 || { echo "Docker daemon not running. Start Docker Desktop (or: colima start --vm-type vz --vz-rosetta --cpu 4 --memory 8 --disk 100)" >&2; exit 2; }
  DOCKER_ARCH="$(docker info --format '{{.Architecture}}')"
  [[ "$DOCKER_ARCH" == "x86_64" || "$DOCKER_ARCH" == "amd64" ]] || echo "Docker host is $DOCKER_ARCH: building linux/amd64 under emulation (slow; needs Rosetta/qemu enabled)."
  DEF_ABS="$(cd "$(dirname "$DEF")" && pwd)/$(basename "$DEF")"; OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
  WORK="$(pwd)"   # %files paths in the .def are relative to this directory
  case "$WORK" in "$HOME"/*) ;; *) echo "NOTE: on macOS the Docker VM shares only \$HOME; a workdir outside it mounts EMPTY and the build fails at def open. Move under \$HOME." >&2 ;; esac
  echo "== apptainer-in-docker ($APPTAINER_IMAGE), platform linux/amd64, workdir $WORK =="
  echo "If the pull fails with an auth error on nvcr.io: 'docker login nvcr.io' with an NGC API key, then re-run."
  # STATUS (27 Oct 2026): this exact recipe built every production image of the authors from July to September 2026
  # (colima, --vz or qemu binfmt, kaczmarj/apptainer 1.4.4). On the same machine after a macOS upgrade it fails at
  # "Failed to spawn stage 1" when %post starts, even for a 3-line alpine def. Until that is understood, macOS users
  # build on a Linux VM or WSL2 (both verified the same day) and copy the .sif back. See references/software-three-doors.md.
  CACHE="${APPTAINER_CACHE_DIR:-$HOME/.apptainer-cache}"; mkdir -p "$CACHE"   # keeps the 10-20 GB base between builds
  docker run --rm --privileged --platform linux/amd64 -v "$WORK:/work" -v "$CACHE:/root/.apptainer" -w /work "$APPTAINER_IMAGE" \
    build "${FLAGS[@]}" "/work/${OUT_ABS#"$WORK"/}" "/work/${DEF_ABS#"$WORK"/}"
fi
echo; ls -lh "$OUT"
# A build killed mid-write leaves a .sif that LOOKS complete. Check the header before trusting it.
if [[ "$MODE" == "native" ]]; then "$BIN" sif list "$OUT" | head -5 || { echo "ERROR: image header unreadable; rebuild with --force" >&2; exit 1; }
else docker run --rm --platform linux/amd64 -v "$WORK:/work" "$APPTAINER_IMAGE" sif list "/work/${OUT_ABS#"$WORK"/}" | head -5 || { echo "ERROR: image header unreadable; rebuild with --force" >&2; exit 1; }; fi
echo "Next: scripts/sync_push.sh images $OUT    (then verify with a debug-queue job: a stale or broken image fails in seconds)"
