#!/bin/bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-nelhua-mango}"
TAG="${TAG:-latest}"

cd "$(dirname "$0")"

BUILD_ARGS=(--pull=newer)
if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
  BUILD_ARGS+=(--build-arg "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
fi

exec podman build "${BUILD_ARGS[@]}" --tag "${IMAGE_NAME}:${TAG}" .
