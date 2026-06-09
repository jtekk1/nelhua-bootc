#!/bin/bash
set -euo pipefail

# Usage: ./build.sh [mango|kde] [tag]
#   ./build.sh             # mango, :latest
#   ./build.sh kde         # kde, :latest
#   ./build.sh kde dev     # kde, :dev
DESKTOP="${1:-${DESKTOP:-mango}}"
TAG="${2:-${TAG:-latest}}"

case "$DESKTOP" in
  mango)
    IMAGE_NAME="${IMAGE_NAME:-nelhua-mango}"
    BASE_IMAGE="${BASE_IMAGE:-quay.io/fedora/fedora-bootc:44}"
    ;;
  kde)
    IMAGE_NAME="${IMAGE_NAME:-nelhua-kde}"
    BASE_IMAGE="${BASE_IMAGE:-quay.io/fedora/fedora-kinoite:44}"
    ;;
  *)
    echo "Unknown desktop: $DESKTOP (expected: mango | kde)" >&2
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

exec podman build "${BUILD_ARGS[@]}" --tag "${IMAGE_NAME}:${TAG}" .
