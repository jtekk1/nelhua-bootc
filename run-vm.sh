#!/bin/bash
set -euo pipefail

# Usage: TYPE=qcow2 ./run-vm.sh [mango|kde]
DESKTOP="${1:-${DESKTOP:-mango}}"
TYPE="${TYPE:-qcow2}"

case "$DESKTOP" in
  mango) IMAGE_NAME="${IMAGE_NAME:-nelhua-mango}" ;;
  kde)   IMAGE_NAME="${IMAGE_NAME:-nelhua-kde}" ;;
  *) echo "Unknown desktop: $DESKTOP (mango | kde)" >&2; exit 1 ;;
esac

cd "$(dirname "$0")"

if [[ "$TYPE" == "iso" ]]; then
  image_file="output/bootiso/install.iso"
else
  image_file="output/${TYPE}/disk.${TYPE}"
fi

if [[ ! -f "$image_file" ]]; then
  echo "Image not found: $image_file" >&2
  case "$TYPE" in
    qcow2) echo "Build first with ./build-qcow2.sh ${DESKTOP}" >&2 ;;
    iso)   echo "Build first with ./build-iso.sh ${DESKTOP}" >&2 ;;
    *)     echo "Unknown TYPE=$TYPE" >&2 ;;
  esac
  exit 1
fi

if command -v systemd-vmspawn >/dev/null 2>&1; then
  exec systemd-vmspawn \
    -M "${IMAGE_NAME}" \
    --console=gui \
    --cpus=2 \
    --ram=$((6*1024*1024*1024)) \
    --network-user-mode \
    --vsock=false --pass-ssh-key=false \
    -i "$image_file"
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
