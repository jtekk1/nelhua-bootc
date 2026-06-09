#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-nelhua-mango}"
IMAGE_REGISTRY_PATH="${IMAGE_REGISTRY_PATH:-ghcr.io/jtekk1/nelhua-mango}"
DESKTOP="${DESKTOP:-mango}"

# Rawhide detection: PRETTY_NAME on rawhide includes "Rawhide" (e.g. "Fedora
# Linux Rawhide.20260609.n.0"). VERSION_ID is just the next-release number
# (e.g. 45) which is indistinguishable from a stable release of the same
# version. Use the PRETTY_NAME signal.
OS_VERSION="$(. /etc/os-release && echo "${VERSION_ID}")"
OS_PRETTY="$(. /etc/os-release && echo "${PRETTY_NAME}")"
IS_RAWHIDE=0
[[ "$OS_PRETTY" == *"Rawhide"* ]] && IS_RAWHIDE=1

log() { printf '\n--- %s ---\n' "$*"; }

# dnf_install: package install helper that adjusts behavior for rawhide.
# On rawhide, --skip-unavailable lets the transaction proceed past missing
# packages (Terra/Tekk haven't published F45 yet). On stable, missing packages
# are a hard fail (regression detection).
#
# NOTE: --skip-unavailable is a per-subcommand flag in dnf5, must come AFTER
# `install`, not before. An earlier version put it in the global slot and was
# rejected with "Unknown argument".
dnf_install() {
  if (( IS_RAWHIDE )); then
    dnf5 -y install --skip-unavailable "$@"
  else
    dnf5 -y install "$@"
  fi
}

enable_repos() {
  log "enable_repos (Fedora ${OS_VERSION}, rawhide=${IS_RAWHIDE})"

  log "  -> RPMFusion nonfree"
  dnf5 -y install \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${OS_VERSION}.noarch.rpm"

  # Terra and Tekk repos: strict on stable (any failure = build fails); soft on
  # rawhide (the upcoming-version .repo may not be published yet). The package
  # installs in install_base also use --skip-unavailable on rawhide so missing
  # dependents (chromium, helium-browser, tekktonic) don't abort the transaction.
  log "  -> Terra GPG key"
  if curl -fsSL "https://repos.fyralabs.com/terra${OS_VERSION}/key.asc" 2>/dev/null | rpm --import - 2>/dev/null; then
    install -Dm0644 /ctx/repos/terra.repo /etc/yum.repos.d/terra.repo
  elif (( IS_RAWHIDE )); then
    log "  -> Terra: SKIPPED — terra${OS_VERSION} not yet published by Fyralabs"
  else
    echo "Terra key URL failed and not on rawhide — refusing to continue" >&2
    exit 1
  fi

  log "  -> Tailscale repo"
  curl -fsSL -o /etc/yum.repos.d/tailscale.repo \
    https://pkgs.tailscale.com/stable/fedora/tailscale.repo

  log "  -> Tekk forgejo repo"
  # forgejo.jtekk.dev has bot protection that 403s default `curl/*` UAs from
  # datacenter IPs (GH runners). Package-manager UAs are typically allow-listed.
  # See .claude/skills/bootc.md "Network reachability from CI".
  if curl -fsSL -A "libdnf (Fedora ${OS_VERSION}; x86_64)" \
       -o /etc/yum.repos.d/tekk-fedora.repo \
       "https://forgejo.jtekk.dev/api/packages/TekkRPM/rpm/tekk-fedora-${OS_VERSION}.repo" 2>/dev/null; then
    : # repo file in place
  elif (( IS_RAWHIDE )); then
    log "  -> Tekk: SKIPPED — tekk-fedora-${OS_VERSION}.repo not yet published"
    rm -f /etc/yum.repos.d/tekk-fedora.repo
  else
    echo "Tekk forgejo repo failed and not on rawhide — refusing to continue" >&2
    exit 1
  fi

  # dnf5 does not ship the `copr` subcommand out of the box — install the plugin first.
  # (dnf4 had it built in; this is a fedora-bootc:44 quirk vs older non-bootc images.)
  log "  -> dnf5 copr plugin"
  dnf5 -y install 'dnf5-command(copr)'

  log "  -> COPRs"
  dnf5 -y copr enable atim/starship
  dnf5 -y copr enable ilyaz/LACT
}

install_base() {
  log "install_base"
  dnf_install \
    curl dbus git gh pciutils tailscale xdg-user-dirs
  systemctl enable tailscaled.service

  dnf_install \
    atuin bat bitwarden-cli eza fd fzf jq lsof plocate ripgrep rsync wget yazi zip zoxide

  dnf_install \
    bluetui btop dialog dust fastfetch gdu glow impala lazygit luarocks ncdu neovim tldr wiremix

  dnf_install satty swappy

  dnf_install \
    cascadiacode-nerd-fonts cascadiamono-nerd-fonts jetbrainsmono-nerd-fonts \
    google-noto-sans-fonts google-noto-serif-fonts google-noto-sans-cjk-fonts \
    google-noto-color-emoji-fonts google-noto-emoji-fonts \
    fontawesome-fonts-all

  dnf_install udiskie wev
  dnf_install asciiquarium cmatrix

  dnf_install \
    chromium flatpak helium-browser imv kitty mpv starship stow tekktonic
}

install_hardware() {
  log "install_hardware"
  # NOTE: libva-intel-driver (legacy i965) is gone in F44. intel-media-driver
  # (iHD) covers Broadwell+, mesa-va-drivers covers older Intel + AMD via Mesa.
  dnf_install \
    mesa-dri-drivers mesa-vulkan-drivers vulkan-loader \
    amd-gpu-firmware amd-ucode-firmware lact \
    intel-media-driver mesa-va-drivers

  # plugdev group used by 50-zsa.rules (ZSA Moonlander/Voyager flashing).
  # Fedora doesn't ship this group by default; create it as a system group.
  # Users still need to be added to plugdev at deploy time.
  groupadd -r plugdev 2>/dev/null || true
}

setup_plymouth() {
  log "setup_plymouth"
  dnf_install plymouth plymouth-theme-solar
  plymouth-set-default-theme solar || true
  # BlueBuild called `dracut -f --regenerate-all` here. In bootc, initramfs is
  # built by bootc-image-builder (or the deployed system), not the container.
  # plan.md flags theme-not-sticking as an open issue and suspected this call.
  # Leaving it OFF; diagnose first, re-enable if needed.
}

install_desktop_mango() {
  log "install_desktop_mango"
  dnf_install \
    awww blueman cliphist greetd grim iwd kanshi mako mangowm \
    pipewire playerctl shotman slurp swaybg swayidle swaylock-effects SwayOSD \
    tuigreet wayland-utils wl-clip-persist wl-clipboard wlopm wlr-randr wlsunset \
    waybar wayland-pipewire-idle-inhibit wofi \
    xdg-desktop-portal-wlr xdg-desktop-portal \
    xinput xorg-x11-server-Xwayland

  # On rawhide some of these may not have installed (--skip-unavailable).
  # systemctl enable returns nonzero if unit doesn't exist; tolerate that.
  systemctl enable greetd.service 2>/dev/null || true
  systemctl enable iwd.service 2>/dev/null || true
}

install_desktop_kde() {
  log "install_desktop_kde"
  # KDE Plasma 6 + SDDM + xdg-desktop-portal-kde come from the kinoite base.
  # Nothing to install in the parity-with-mango sense — kinoite already covers
  # the compositor + login manager + portal that mango.yml installed for the
  # Wayland WM. Add Nelhua-opinionated KDE niceties here as they're decided
  # (KDE Connect, breeze-dark default, etc. — tracked in plan.md K4).
  :
}

install_extras() {
  log "install_extras"
  # gaming
  dnf_install gamescope mangohud protontricks
  # dev
  dnf_install direnv make
  # virt — tools to boot/build VMs from this OS (./run-vm.sh, dogfooding bootc images).
  # edk2-ovmf:             UEFI firmware blob for guests
  # systemd-container:     ships systemd-vmspawn (and nspawn)
  # qemu-system-x86-core:  the actual x86 VM
  # qemu-{char,ui,audio}-spice + qemu-ui-gtk + qemu-device-display-virtio-gpu:
  #   GTK + SPICE backends + virtio GPU. systemd-vmspawn --console=gui asks qemu
  #   for `-display gtk`; without qemu-ui-gtk qemu falls back to VNC silently.
  dnf_install \
    edk2-ovmf systemd-container \
    qemu-system-x86-core \
    qemu-char-spice qemu-ui-spice-app qemu-ui-gtk qemu-audio-spice \
    qemu-device-display-virtio-gpu
}

install_superfile() {
  log "install_superfile"
  if [[ -x /usr/bin/spf ]]; then
    return 0
  fi
  local arch tag tmp archive binary
  case "$(uname -m)" in
    x86_64)  arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo "Unsupported arch: $(uname -m)" >&2; return 1 ;;
  esac
  tag="$(curl -fsSL https://api.github.com/repos/yorukot/superfile/releases/latest \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
  tmp="$(mktemp -d)"
  archive="superfile-linux-${tag}-${arch}.tar.gz"
  curl -fsSL "https://github.com/yorukot/superfile/releases/download/${tag}/${archive}" \
    -o "$tmp/spf.tar.gz"
  tar -xzf "$tmp/spf.tar.gz" -C "$tmp"
  binary="$(find "$tmp" -name spf -type f -executable | head -1)"
  [[ -n "$binary" ]] || { echo "spf binary not found in tarball" >&2; return 1; }
  install -m 755 "$binary" /usr/bin/spf
  rm -rf "$tmp"
}

apply_files() {
  log "apply_files"
  rsync -rlptD /system-files/ /
}

enable_first_boot_services() {
  log "enable_first_boot_services"
  # Both are oneshot units guarded by ConditionPathExists so they run exactly
  # once per fresh deployment. Units live in files/system/etc/systemd/system/
  # and were just rsync'd in by apply_files.
  systemctl enable brew-setup.service
  systemctl enable nix-setup.service
}

remove_unwanted() {
  log "remove_unwanted"
  dnf5 -y remove firefox firefox-langpacks || true
}

apply_signing() {
  log "apply_signing"
  install -Dm0644 /ctx/cosign.pub "/etc/pki/containers/${IMAGE_NAME}.pub"

  install -d /etc/containers/registries.d
  cat > "/etc/containers/registries.d/${IMAGE_NAME}.yaml" <<EOF
docker:
  ${IMAGE_REGISTRY_PATH}:
    use-sigstore-attachments: true
EOF

  python3 - <<EOF
import json, pathlib
p = pathlib.Path('/etc/containers/policy.json')
data = json.loads(p.read_text())
data.setdefault('transports', {}).setdefault('docker', {})['${IMAGE_REGISTRY_PATH}'] = [{
  'type': 'sigstoreSigned',
  'keyPath': '/etc/pki/containers/${IMAGE_NAME}.pub',
  'signedIdentity': {'type': 'matchRepository'},
}]
p.write_text(json.dumps(data, indent=4))
EOF
}

apply_os_release() {
  log "apply_os_release"
  local pretty
  case "$DESKTOP" in
    mango) pretty="Nelhua-Linux (Mango Edition)" ;;
    kde)   pretty="Nelhua-Linux (KDE)" ;;
    *)     pretty="Nelhua-Linux" ;;
  esac
  sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${pretty}\"/" /etc/os-release
}

cleanup_var_state() {
  # Pure runtime state that shouldn't ship in image layers. bootc lint flags
  # these as `Found non-directory/non-symlink files in /var` otherwise.
  log "cleanup_var_state"
  rm -rf /var/lib/dnf /var/lib/plocate
  rm -f  /var/lib/authselect/checksum
}

generate_var_tmpfiles() {
  # bootc resets /var from /usr/share/factory/var/ on first boot via systemd-
  # tmpfiles. Without explicit tmpfiles.d entries, package-installed /var/lib
  # directories (AccountsService, blueman, greetd, ...) vanish at first boot
  # and services that expect them misbehave. Walk what's left and emit `d`
  # lines for directories and `L+` lines for symlinks.
  #
  # Run AFTER cleanup_var_state so we don't emit entries for state we just
  # deleted; run BEFORE final cleanup() so /var/log etc. aren't yet wiped.
  log "generate_var_tmpfiles"
  local conf=/usr/lib/tmpfiles.d/nelhua-bootc-var.conf
  {
    echo "# Auto-generated by build_files/build.sh."
    echo "# Recreates /var/lib state baked at build time so it survives bootc's"
    echo "# first-boot /var reset. See .claude/skills/bootc.md (var-tmpfiles)."
    if [[ -d /var/lib ]]; then
      find /var/lib -mindepth 1 -type d -printf 'd /var/lib/%P 0%m %u %g - -\n'
      find /var/lib -mindepth 1 -type l -printf 'L+ /var/lib/%P - - - - %l\n'
    fi
  } > "$conf"
}

cleanup() {
  log "cleanup"
  dnf5 -y copr disable atim/starship || true
  dnf5 -y copr disable ilyaz/LACT || true
  dnf5 clean all
  # Comprehensive scrub: build-time state in /var that won't survive the
  # first-boot reset, plus runtime-only paths that bootc lint flags
  # (nonempty-run-tmp).
  rm -rf /var/cache/* /var/log/* /tmp/* /var/tmp/*
  rm -rf /run/* 2>/dev/null || true
}

install_desktop() {
  case "$DESKTOP" in
    mango) install_desktop_mango ;;
    kde)   install_desktop_kde ;;
    *) echo "Unknown DESKTOP='$DESKTOP' (expected mango|kde)" >&2; exit 1 ;;
  esac
}

main() {
  log "build (desktop=${DESKTOP}, image=${IMAGE_NAME}, base=$(. /etc/os-release && echo "${PRETTY_NAME}"))"
  enable_repos
  install_base
  install_hardware
  setup_plymouth
  install_desktop      # dispatches to install_desktop_mango or install_desktop_kde
  install_extras
  install_superfile
  apply_files          # ship system tree (including brew-setup + nix-setup units)
  enable_first_boot_services
  remove_unwanted
  apply_signing
  apply_os_release
  cleanup_var_state    # scrub /var/lib state (dnf cache, plocate, etc.)
  generate_var_tmpfiles # emit tmpfiles.d for surviving /var/lib dirs + symlinks
  cleanup              # final pass: cache/log/tmp/run
}

main "$@"
