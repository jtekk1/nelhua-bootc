#!/bin/bash
set -euo pipefail

# Usage: ./build-iso.sh [mango|kde|kinectic|kde-nvidia-open|kinectic-nvidia-open] [tag]
#
# Builds an Anaconda installer ISO for the chosen desktop variant. Local only —
# there's no cloud host for these yet, so the ISO lands in ./output/bootiso/
# and stays there.
#
# Image source: always pulled fresh from ${REGISTRY}/${IMAGE_NAME}:${TAG}.
# Whatever you may have built locally with ./build.sh is ignored — this
# script's contract is "ISO of the published image at that tag right now".
# If you want to ISO a locally-built image without going through the
# registry, set LOCAL=1 to skip the pull (script then expects the image
# to be present in rootful podman storage as localhost/${IMAGE_NAME}:${TAG}).
#
# Recent bootc-image-builder stopped auto-pulling target images at run time
# ("image not known" error), so the pull has to happen up-front in this
# script before invoking BIB.

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
REGISTRY="${REGISTRY:-ghcr.io/jtekk1}"

cd "$(dirname "$0")"
CONFIG="${CONFIG:-$(pwd)/disk_config/iso-${DESKTOP}.toml}"
mkdir -p output

if [[ ! -f "$CONFIG" ]]; then
  echo "Config not found: $CONFIG" >&2
  exit 1
fi

if [[ -n "${LOCAL:-}" ]]; then
  # User opted out of the registry pull. Verify the image is actually in
  # rootful storage (BIB-under-sudo can't see rootless storage).
  if ! sudo podman image exists "localhost/${IMAGE_NAME}:${TAG}"; then
    echo "LOCAL=1 set but localhost/${IMAGE_NAME}:${TAG} not in rootful podman storage." >&2
    echo "Either build the image into rootful storage, or copy it across:" >&2
    echo "  sudo podman image scp \"\${UID}@localhost::${IMAGE_NAME}:${TAG}\" \\" >&2
    echo "                        \"root@localhost::${IMAGE_NAME}:${TAG}\"" >&2
    exit 1
  fi
else
  # Default path: always pull the latest published image. Tagging it as
  # localhost/<image>:<tag> keeps the BIB invocation below symmetric with
  # the LOCAL=1 path.
  echo "Pulling ${REGISTRY}/${IMAGE_NAME}:${TAG} into rootful podman storage..."
  sudo podman pull "${REGISTRY}/${IMAGE_NAME}:${TAG}"
  sudo podman tag "${REGISTRY}/${IMAGE_NAME}:${TAG}" "localhost/${IMAGE_NAME}:${TAG}"
fi

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
  --type anaconda-iso \
  --use-librepo=True \
  "localhost/${IMAGE_NAME}:${TAG}"

sudo chown -R "$USER:$USER" output/

# Rename to nelhua-{desktop}-{YYYYMMDD}.iso and prune everything else BIB
# produced (intermediate qcow2 dirs, manifest-*.json sidecars, the now-empty
# bootiso/ subdir). Same-day re-runs overwrite the previous ISO.
DATE="$(date +%Y%m%d)"
FINAL="output/nelhua-${DESKTOP}-${DATE}.iso"
mv -f "output/bootiso/install.iso" "$FINAL"
rm -rf output/bootiso output/qcow2 output/manifest-*.json

echo "ISO: $(pwd)/${FINAL}"
