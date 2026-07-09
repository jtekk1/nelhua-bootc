#!/bin/bash
set -euo pipefail

# Usage: ./build-qcow2.sh [mango|kde|kinectic|kde-nvidia-open|kinectic-nvidia-open] [tag]
DESKTOP="${1:-${DESKTOP:-mango}}"
TAG="${2:-${TAG:-latest}}"

case "$DESKTOP" in
  mango)                IMAGE_NAME="${IMAGE_NAME:-nelhua-mango}" ;;
  kde)                  IMAGE_NAME="${IMAGE_NAME:-nelhua-kde}" ;;
  kinectic)             IMAGE_NAME="${IMAGE_NAME:-nelhua-kinectic}" ;;
  kde-nvidia-open)      IMAGE_NAME="${IMAGE_NAME:-nelhua-kde-nvidia-open}" ;;
  kinectic-nvidia-open) IMAGE_NAME="${IMAGE_NAME:-nelhua-kinectic-nvidia-open}" ;;
  *) echo "Unknown desktop: $DESKTOP (mango | kde | kinectic | kde-nvidia-open | kinectic-nvidia-open)" >&2; exit 1 ;;
esac

BIB_IMAGE="${BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}"

cd "$(dirname "$0")"
CONFIG="${CONFIG:-$(pwd)/disk_config/disk.toml}"
mkdir -p output

# bootc-image-builder runs under sudo podman and reads from /var/lib/containers/storage
# (rootful). `./build.sh` builds into the rootless user store. Bridge them.
ensure_rootful_image() {
  local user_id root_id tmpdir
  user_id="$(podman images --filter reference="${IMAGE_NAME}:${TAG}" --format '{{.ID}}' | head -1 || true)"
  root_id="$(sudo podman images --filter reference="${IMAGE_NAME}:${TAG}" --format '{{.ID}}' | head -1 || true)"

  if [[ -z "$user_id" && -z "$root_id" ]]; then
    echo "Image ${IMAGE_NAME}:${TAG} not found in rootless or rootful podman." >&2
    echo "Build it first: ./build.sh ${DESKTOP}" >&2
    exit 1
  fi

  if [[ -n "$user_id" && "$user_id" != "$root_id" ]]; then
    echo "Copying ${IMAGE_NAME}:${TAG} from rootless -> rootful podman..."
    tmpdir="$(mktemp -d -p "$(pwd)" .scp.XXXXXX)"
    sudo TMPDIR="$tmpdir" podman image scp \
      "${UID}@localhost::${IMAGE_NAME}:${TAG}" \
      "root@localhost::${IMAGE_NAME}:${TAG}"
    rm -rf "$tmpdir"
  fi
}

ensure_rootful_image

sudo podman run \
  --rm -it \
  --privileged \
  --pull=newer \
  --net=host \
  --security-opt label=type:unconfined_t \
  -v "$(realpath "$CONFIG"):/config.toml:ro" \
  -v "$(pwd)/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  "$BIB_IMAGE" \
  --type qcow2 \
  --use-librepo=True \
  --rootfs=btrfs \
  "localhost/${IMAGE_NAME}:${TAG}"

sudo chown -R "$USER:$USER" output/
echo "Output: $(pwd)/output/qcow2/"
