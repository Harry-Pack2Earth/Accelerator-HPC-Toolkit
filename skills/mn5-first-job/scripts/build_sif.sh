#!/usr/bin/env bash
# build_sif.sh — build a linux/amd64 Apptainer image, on whatever machine this is.
# Usage: scripts/build_sif.sh --def <file.def> --out <image.sif> [--force] [--mode native|docker|docker-def]
#
# The cluster is x86_64 (linux/amd64). The image must be too, whatever your laptop is.
#   native      Linux x86_64 / WSL2 with apptainer installed: build from the .def (--fakeroot, then sudo). Verified.
#   docker      macOS, or any machine with Docker but no apptainer: Docker builds the image from the Dockerfile next
#               to the .def (same content), forced to linux/amd64, then apptainer (in a container) converts it to .sif
#               straight from the Docker daemon. Nothing runs inside apptainer, so no privileged nesting and no
#               %post under emulation. Status: see TESTING.md in the repository root.
#   docker-def  the older recipe: apptainer itself inside a privileged amd64 container, building from the .def. It
#               built every image of the authors on macOS 26 (July to Sept 2026) and stopped working on the same
#               machine on macOS 27 / current colima ("Failed to spawn stage 1", even for a native arm64 def). Kept
#               for machines where it still works.
# On Apple Silicon enable amd64 emulation (Docker Desktop: Settings > General > Rosetta; colima: --vz-rosetta or qemu
# binfmt, both fine for docker mode). "exec format error" means it is off.
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
# NOTE: every "${FLAGS[@]}" below is written ${FLAGS[@]+"${FLAGS[@]}"}: stock macOS /bin/bash is 3.2, where an
# empty array under `set -u` is an unbound variable and the script would die at the convert step, after the full build.
START_TS="$(date +%s)"
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
docker_prep() {
  docker info >/dev/null 2>&1 || { echo "Docker daemon not running. Start Docker Desktop (or: colima start --vm-type vz --cpu 4 --memory 8 --disk 100)" >&2; exit 2; }
  DOCKER_ARCH="$(docker info --format '{{.Architecture}}')"
  [[ "$DOCKER_ARCH" == "x86_64" || "$DOCKER_ARCH" == "amd64" ]] || echo "Docker host is $DOCKER_ARCH: building linux/amd64 under emulation (slow; needs Rosetta/qemu enabled)."
  DEF_DIR="$(cd "$(dirname "$DEF")" && pwd)"; DEF_ABS="${DEF_DIR}/$(basename "$DEF")"; OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
  WORK="$(pwd)"   # %files / COPY paths are relative to this directory
  case "$WORK" in "$HOME"/*) ;; *) echo "NOTE: on macOS the Docker VM shares only \$HOME; a workdir outside it mounts EMPTY and the build fails at def open. Move under \$HOME." >&2 ;; esac
  CACHE="${APPTAINER_CACHE_DIR:-$HOME/.apptainer-cache}"; mkdir -p "$CACHE"   # keeps pulled layers between builds
}
if [[ "$MODE" == "native" ]]; then
  BIN="$(command -v apptainer || command -v singularity)"
  [[ "$(uname -m)" == "x86_64" ]] || { echo "ERROR: native build on $(uname -m) would produce a non-x86_64 image. Use --mode docker (emulated) or an x86_64 Linux machine." >&2; exit 2; }
  echo "== native build with $BIN (--fakeroot) =="
  if ! "$BIN" build --fakeroot ${FLAGS[@]+"${FLAGS[@]}"} "$OUT" "$DEF" 2> >(tee /tmp/build_sif.err >&2); then
    # Two known failures of --fakeroot: no subuid mapping for the user, and WSL2, where apptainer tries to mount
    # binfmt_misc that Windows interop already mounted ("failed to mount binfmt_misc filesystem: invalid argument").
    # Both are fixed by building as real root, which every Linux/WSL user with sudo can do. Verified Oct 2026.
    if command -v sudo >/dev/null 2>&1; then
      echo "fakeroot build failed ($(grep -m1 -oE 'FATAL.*' /tmp/build_sif.err || echo see above)); retrying with sudo" >&2
      sudo "$BIN" build ${FLAGS[@]+"${FLAGS[@]}"} "$OUT" "$DEF" || { echo "sudo build failed too; see the messages above" >&2; exit 1; }
      sudo chown "$(id -u):$(id -g)" "$OUT"
    else
      echo "fakeroot build failed and no sudo: ask the admin to add you to /etc/subuid, or build on another machine" >&2; exit 1
    fi
  fi
elif [[ "$MODE" == "docker" ]]; then
  docker_prep
  DOCKERFILE="${DEF_DIR}/Dockerfile"
  [[ -f "$DOCKERFILE" ]] || { echo "docker mode needs a Dockerfile next to $DEF (copy templates/Dockerfile; keep it in step with the .def)" >&2; exit 2; }
  TAG="hpc-first-job/$(basename "${OUT%.sif}"):build"
  echo "== 1/2 docker build (linux/amd64) -> $TAG =="
  echo "If the pull fails with an auth error on nvcr.io: 'docker login nvcr.io' with an NGC API key, then re-run."
  docker build --platform linux/amd64 -t "$TAG" -f "$DOCKERFILE" "$WORK"
  echo "== 2/2 convert $TAG -> $OUT (apptainer in a container reads the Docker daemon; nothing runs) =="
  docker run --rm --platform linux/amd64 -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$WORK:/work" -v "$CACHE:/root/.apptainer" -w /work "$APPTAINER_IMAGE" \
    build ${FLAGS[@]+"${FLAGS[@]}"} "/work/${OUT_ABS#"$WORK"/}" "docker-daemon://${TAG}"
else
  docker_prep
  echo "== docker-def: apptainer-in-docker ($APPTAINER_IMAGE), platform linux/amd64, workdir $WORK =="
  docker run --rm --privileged --platform linux/amd64 -v "$WORK:/work" -v "$CACHE:/root/.apptainer" -w /work "$APPTAINER_IMAGE" \
    build ${FLAGS[@]+"${FLAGS[@]}"} "/work/${OUT_ABS#"$WORK"/}" "/work/${DEF_ABS#"$WORK"/}"
fi
echo
# The image must be NEW: a failed build under --force can leave an older file in place and a wrapper would call it built.
[[ -s "$OUT" ]] || { echo "ERROR: $OUT is missing or empty after the build" >&2; exit 1; }
OUT_TS="$(stat -f %m "$OUT" 2>/dev/null || stat -c %Y "$OUT")"
[[ "$OUT_TS" -ge "$START_TS" ]] || { echo "ERROR: $OUT predates this build (an older image is still there); rebuild with --force" >&2; exit 1; }
ls -lh "$OUT"
# A build killed mid-write leaves a .sif that LOOKS complete. Check the header before trusting it.
if [[ "$MODE" == "native" ]]; then "$BIN" sif list "$OUT" | tail -3 || { echo "ERROR: image header unreadable; rebuild with --force" >&2; exit 1; }
else docker run --rm --platform linux/amd64 -v "$WORK:/work" "$APPTAINER_IMAGE" sif list "/work/${OUT_ABS#"$WORK"/}" | tail -3 || { echo "ERROR: image header unreadable; rebuild with --force" >&2; exit 1; }; fi
echo "Next: scripts/sync_push.sh images $OUT    (then verify with a debug-queue job: a stale or broken image fails in seconds)"
