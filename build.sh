#!/bin/bash
set -euo pipefail

# Usage: ./build.sh [mango|kde|kinectic|kde-nvidia-open|kinectic-nvidia-open] [tag]
#   ./build.sh                       # mango, :latest
#   ./build.sh kde                   # kde, :latest
#   ./build.sh kde dev               # kde, :dev
#   ./build.sh kinectic              # kinectic (KineticWE), :latest
#   ./build.sh kde-nvidia-open       # KDE + NVIDIA open kernel modules
#   ./build.sh kinectic-nvidia-open  # KineticWE + NVIDIA open kernel modules
DESKTOP="${1:-${DESKTOP:-mango}}"
TAG="${2:-${TAG:-latest}}"

# CONTAINERFILE selects which Dockerfile the build uses. Any *-nvidia-open
# flavor needs the two extra akmods FROM stages that only live in
# Containerfile.nvidia-open — plain Containerfile has no /akmods-rpms
# mount and install_nvidia_open() would fail its "no kmod-nvidia RPMs
# found" precondition.
CONTAINERFILE="./Containerfile"

case "$DESKTOP" in
  mango)
    IMAGE_NAME="${IMAGE_NAME:-nelhua-mango}"
    BASE_IMAGE="${BASE_IMAGE:-quay.io/fedora/fedora-bootc:44}"
    ;;
  kde)
    IMAGE_NAME="${IMAGE_NAME:-nelhua-kde}"
    BASE_IMAGE="${BASE_IMAGE:-quay.io/fedora/fedora-kinoite:44}"
    ;;
  kinectic)
    IMAGE_NAME="${IMAGE_NAME:-nelhua-kinectic}"
    BASE_IMAGE="${BASE_IMAGE:-quay.io/fedora/fedora-kinoite:44}"
    ;;
  kde-nvidia-open)
    IMAGE_NAME="${IMAGE_NAME:-nelhua-kde-nvidia-open}"
    BASE_IMAGE="${BASE_IMAGE:-quay.io/fedora/fedora-kinoite:44}"
    CONTAINERFILE="./Containerfile.nvidia-open"
    ;;
  kinectic-nvidia-open)
    IMAGE_NAME="${IMAGE_NAME:-nelhua-kinectic-nvidia-open}"
    BASE_IMAGE="${BASE_IMAGE:-quay.io/fedora/fedora-kinoite:44}"
    CONTAINERFILE="./Containerfile.nvidia-open"
    ;;
  *)
    echo "Unknown desktop: $DESKTOP (expected: mango | kde | kinectic | kde-nvidia-open | kinectic-nvidia-open)" >&2
    exit 1
    ;;
esac

IMAGE_REGISTRY_PATH="${IMAGE_REGISTRY_PATH:-ghcr.io/jtekk1/${IMAGE_NAME}}"

cd "$(dirname "$0")"

BUILD_ARGS=(--pull=newer)
BUILD_ARGS+=(--build-arg "BASE_IMAGE=${BASE_IMAGE}")
BUILD_ARGS+=(--build-arg "IMAGE_NAME=${IMAGE_NAME}")
BUILD_ARGS+=(--build-arg "IMAGE_REGISTRY_PATH=${IMAGE_REGISTRY_PATH}")
BUILD_ARGS+=(--build-arg "DESKTOP=${DESKTOP}")
if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
  BUILD_ARGS+=(--build-arg "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
fi

exec podman build "${BUILD_ARGS[@]}" -f "${CONTAINERFILE}" --tag "${IMAGE_NAME}:${TAG}" .
