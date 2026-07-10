#!/bin/bash
set -euo pipefail

# Usage: TYPE=qcow2 ./run-vm.sh [mango|kde|kinectic|kde-nvidia-open|kinectic-nvidia-open]
#
# Env overrides:
#   ISO_PATH=<file>   point at a specific ISO instead of the newest match in output/
#   TARGET=<file>     scratch install target for ISO boots (default: output/<flavor>-install-target.raw)
#   NO_VMSPAWN=1      skip systemd-vmspawn and use the qemu-system-x86_64 fallback
DESKTOP="${1:-${DESKTOP:-mango}}"
TYPE="${TYPE:-qcow2}"

case "$DESKTOP" in
  mango)                IMAGE_NAME="${IMAGE_NAME:-nelhua-mango}" ;;
  kde)                  IMAGE_NAME="${IMAGE_NAME:-nelhua-kde}" ;;
  kinectic)             IMAGE_NAME="${IMAGE_NAME:-nelhua-kinectic}" ;;
  kde-nvidia-open)      IMAGE_NAME="${IMAGE_NAME:-nelhua-kde-nvidia-open}" ;;
  kinectic-nvidia-open) IMAGE_NAME="${IMAGE_NAME:-nelhua-kinectic-nvidia-open}" ;;
  *) echo "Unknown desktop: $DESKTOP (mango | kde | kinectic | kde-nvidia-open | kinectic-nvidia-open)" >&2; exit 1 ;;
esac

cd "$(dirname "$0")"

if [[ "$TYPE" == "iso" ]]; then
  # build-iso.sh renames its output to output/nelhua-<flavor>-<YYYYMMDD>.iso
  # and removes output/bootiso/, so we glob for the newest match. The [0-9]*
  # suffix keeps the glob for e.g. DESKTOP=kinectic from also matching
  # nelhua-kinectic-nvidia-open-*.iso. ISO_PATH overrides for one-off
  # diagnostics against a specific dated ISO.
  image_file="${ISO_PATH:-$(ls -1t output/nelhua-${DESKTOP}-[0-9]*.iso 2>/dev/null | head -1 || true)}"
else
  image_file="output/${TYPE}/disk.${TYPE}"
fi

if [[ -z "${image_file:-}" || ! -f "$image_file" ]]; then
  echo "Image not found for DESKTOP=$DESKTOP TYPE=$TYPE" >&2
  case "$TYPE" in
    qcow2) echo "Build first with ./build-qcow2.sh ${DESKTOP}" >&2 ;;
    iso)   echo "Build first with ./build-iso.sh ${DESKTOP} (or set ISO_PATH=<file>)" >&2 ;;
    *)     echo "Unknown TYPE=$TYPE" >&2 ;;
  esac
  exit 1
fi

echo "Using image: $image_file"

# ISO installs need a scratch target disk to install onto. Sparse raw file
# via truncate — no qemu-img dependency, and qemu is happy with format=raw for
# an install target. Reuse across runs so a partial install can be inspected;
# delete to redo cleanly.
if [[ "$TYPE" == "iso" ]]; then
  TARGET="${TARGET:-output/${DESKTOP}-install-target.raw}"
  if [[ ! -f "$TARGET" ]]; then
    echo "Creating install target disk: $TARGET (40G sparse)"
    truncate -s 40G "$TARGET"
  else
    echo "Reusing install target: $TARGET (rm to redo cleanly)"
  fi
fi

# vmspawn is the preferred path but fails hard on hosts whose qemu-kvm lacks
# virtio-vga-gl ("Virtio VGA not available"). NO_VMSPAWN=1 skips it; otherwise
# we try vmspawn and fall through to qemu on failure.
if [[ -z "${NO_VMSPAWN:-}" ]] && command -v systemd-vmspawn >/dev/null 2>&1; then
  if systemd-vmspawn \
      -M "${IMAGE_NAME}" \
      --console=gui \
      --cpus=2 \
      --ram=$((6*1024*1024*1024)) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i "$image_file"; then
    exit 0
  fi
  echo "systemd-vmspawn exited non-zero; falling back to qemu-system-x86_64..." >&2
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  cat >&2 <<EOF
Neither systemd-vmspawn nor qemu-system-x86_64 found on this host.
Install both + UEFI firmware:
  sudo rpm-ostree install systemd-container qemu-system-x86-core edk2-ovmf
  systemctl reboot
(Next ./build.sh bake includes these by default.)
EOF
  exit 1
fi

# ISOs boot as CDROM with a separate virtio target to install onto; qcow2s are
# already-installed rootfs images that boot directly. -vga std sidesteps hosts
# whose qemu-kvm lacks virtio-vga (same failure vmspawn hits).
if [[ "$TYPE" == "iso" ]]; then
  exec qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,accel=kvm \
    -cpu host \
    -smp 2 \
    -m 6G \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
    -cdrom "$image_file" \
    -boot d \
    -drive "file=${TARGET},if=virtio,format=raw" \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -vga std \
    -display gtk
fi

exec qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -smp 2 \
  -m 6G \
  -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
  -drive "file=${image_file},if=virtio,format=${TYPE}" \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -display gtk
