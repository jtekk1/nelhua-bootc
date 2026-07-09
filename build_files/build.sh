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

  log "  -> Charm repo (gum, glow, vhs, soft-serve)"
  # Charm's GPG key is vendored (files/dnf/charm.key) rather than fetched.
  # repo.charm.sh is Gemfury-backed and has been unreliable — three
  # consecutive CI runs hit `curl: (7) Failed to connect ... after 79s`
  # on the gpg.key path while the same host resolved fine locally elsewhere.
  # The vendored key is rsa4096 (fingerprint ED927B38…4DFD35C), expires
  # 2027-07-13. baseurl= stays remote for package fetch; charm.repo's
  # gpgkey= now points at the vendored key at /etc/pki/rpm-gpg/… so
  # runtime dnf-refresh doesn't refetch the key either.
  install -Dm0644 /ctx/repos/charm.key /etc/pki/rpm-gpg/RPM-GPG-KEY-charm
  rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-charm
  install -Dm0644 /ctx/repos/charm.repo /etc/yum.repos.d/charm.repo

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
  # kwin-effects-glass: maintained by AMA147000 (not the upstream dev). The
  # COPR project's available chroots are F42/F43/F44 only — no
  # fedora-rawhide-x86_64. `dnf5 copr enable` errors out hard
  # ("Chroot not found in the given Copr project") if we try on rawhide,
  # so skip there. install_desktop_kde() uses dnf_install which respects
  # --skip-unavailable on rawhide, so the missing package no-ops cleanly.
  # Mirrors the Terra/Tekk SKIP-on-rawhide pattern above.
  if (( IS_RAWHIDE )); then
    log "  -> COPR ama1470/kwin-effects-glass: SKIPPED on rawhide (no F45 chroot yet)"
  else
    dnf5 -y copr enable ama1470/kwin-effects-glass
  fi
}

install_base() {
  log "install_base"
  dnf_install \
    curl dbus git gh pciutils tailscale xdg-user-dirs
  systemctl enable tailscaled.service

  dnf_install \
    atuin bat bitwarden-cli eza fd fzf jq lsof plocate ripgrep rsync wget yazi zip zoxide

  dnf_install \
    bluetui btop dust fastfetch gdu glow gum impala lazygit luarocks ncdu neovim tldr wiremix

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
  # Power profiles + biometrics are inherited from the base:
  # - kinoite/fedora-bootc both pre-install fprintd; nothing to do for KDE
  #   biometrics — Plasma 6's kcm_fingerprint hits fprintd via DBus.
  # - kinoite ships `tuned-ppd` (TuneD with a PPD-API shim) — KDE's power
  #   KCM speaks PPD, so the KCM works the same whether the backend is
  #   PPD or tuned-ppd. Layering `power-profiles-daemon` here would
  #   hard-conflict with the tuned-ppd already in /usr (both claim the
  #   `ppd-service` capability). Leave the base's choice in place; if a
  #   user wants pure PPD they can `rpm-ostree swap tuned-ppd power-
  #   profiles-daemon` per-deployment.
  # ZSA Moonlander/Voyager device access: 50-zsa.rules uses TAG+="uaccess",
  # so the active session user gets device access via systemd-logind. No
  # plugdev group / no per-user usermod step.
}

setup_plymouth() {
  log "setup_plymouth"
  # The `nelhua` theme is bundled at files/system/usr/share/plymouth/themes/
  # nelhua/, so this MUST run after apply_files() — until then the theme dir
  # isn't on disk and plymouth-set-default-theme has nothing to point at.
  # See main() ordering for the move-after.
  #
  # Dropped `plymouth-theme-solar` install — we ship our own and the upstream
  # theme would be dead weight.
  dnf_install plymouth
  plymouth-set-default-theme nelhua || true
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
  # KDE Plasma 6 + plasma-login-manager + xdg-desktop-portal-kde come from the
  # kinoite base. (Fedora Kinoite F44 ships plasma-login-manager, the new
  # Wayland-native KDE login screen — NOT SDDM. Theming model is different:
  # see files/system/usr/share/plasma/look-and-feel/org.nelhua.linux.default/
  # and files/system/etc/plasmalogin.conf.d/10-nelhua.conf.)
  #
  # Nothing to install in the parity-with-mango sense — kinoite already covers
  # the compositor + login manager + portal. Add Nelhua-opinionated KDE
  # niceties here as they're decided.

  # kwin-effects-glass: fork of Plasma 6 blur with force-blur + refraction.
  # Plugin lib installs as `glass.so` → enabled via [Plugins]glassEnabled=true
  # in /etc/xdg/kwinrc (shipped at files/system/etc/xdg/kwinrc). Glass
  # supersedes stock blur (it IS forked from blur), so we also set
  # blurEnabled=false there to avoid double-render.
  # F44 ships Plasma 6.6.5 — within the upstream-supported window (6.6 +
  # Wayland-only; Kinoite defaults to Wayland so this isn't a constraint).
  dnf_install kwin-effects-glass

  # Sweet look-and-feel themes (Mars + Ambar Blue). KDE-only — LAFs
  # ship under /usr/share/plasma/look-and-feel/ and only appear in the
  # KCM picker on Plasma desktops. Default LAF (org.nelhua.linux.default)
  # is unaffected; these are *available* options for users to pick.
  install_lookandfeel_themes

  # Third-party KWin effects bundle (Burn-My-Windows, Kinetic, Geometry
  # Change, Squash-Plus). Drops effect kpackages into /usr/share/kwin/
  # effects/ — *available* in System Settings → Window Effects but not
  # enabled by default. Same posture as the LAFs above.
  install_kwin_effects
}

install_desktop_kinectic() {
  log "install_desktop_kinectic"
  # Same kinoite base as the KDE flavor — Plasma 6 + plasma-login-manager +
  # xdg-desktop-portal-kde come from the base. Kinectic swaps the stock KWin
  # family (kwin, kwin-common, kwin-libs, kwin-wayland, kglobalacceld) for
  # KineticWE, a native-tiling KWin fork by theblackdon
  # (https://gitlab.com/theblackdon/kineticwe). The COPR-built RPM
  # Provides+Obsoletes all five, so a plain `dnf install kineticwe`
  # performs the swap in one transaction — no --allowerasing / no
  # dnf swap gymnastics.
  #
  # Reuse the theme + JS-effect layers from the KDE flavor: KWin's JS
  # scripting API and /usr/share/plasma paths are stable across the fork,
  # so LAFs and JS effect kpackages ride through cleanly.
  #
  # NOT reused: kwin-effects-glass. It's a C++ KWin plugin compiled against
  # stock kwin's headers; loading it into kineticwe.so is an ABI gamble
  # until upstream confirms compatibility.
  install_lookandfeel_themes
  install_kwin_effects

  # theblackdon/kineticwe COPR chroots: fedora-44 + fedora-rawhide only.
  # `dnf5 copr enable` errors hard if the chroot is missing; guard on
  # rawhide the same way enable_repos() guards ama1470/kwin-effects-glass.
  # dnf_install below uses --skip-unavailable on rawhide, so a failed
  # enable no-ops cleanly there (rawhide is continue-on-error already).
  log "  -> COPR theblackdon/kineticwe"
  if (( IS_RAWHIDE )); then
    dnf5 -y copr enable theblackdon/kineticwe || \
      log "  -> COPR kineticwe: SKIPPED on rawhide (chroot not yet published)"
  else
    dnf5 -y copr enable theblackdon/kineticwe
  fi

  dnf_install kineticwe
}

install_nvidia_open() {
  log "install_nvidia_open"
  # Containerfile.nvidia-open bind-mounts:
  #   /akmods-rpms/         <- ghcr.io/ublue-os/akmods:${AKMODS_TAG}/rpms
  #   /akmods-nvidia-rpms/  <- ghcr.io/ublue-os/akmods-nvidia-open:${AKMODS_NVIDIA_OPEN_TAG}/rpms
  # See Containerfile.nvidia-open for the "tags must match kernel exactly"
  # invariant. Renovate keeps AKMODS_TAG / AKMODS_NVIDIA_OPEN_TAG bumped in
  # step with the kinoite base's kernel.

  # Kmod RPM name embeds the exact kernel it was built for:
  #   kmod-nvidia-<kernel-ver>-<driver-ver>.<arch>.rpm
  # If the base image's kernel drifts past what the akmods tag was built
  # against, modprobe refuses to load nvidia.ko at first boot (-EINVAL /
  # "invalid module format"). Detect the mismatch at build time so kernel
  # drift between BASE_IMAGE and AKMODS_NVIDIA_OPEN_TAG surfaces as red
  # CI, not as an unbootable image landing in production.
  local KERNEL_VER
  KERNEL_VER=$(rpm -q kernel-core --qf '%{V}-%{R}.%{ARCH}')
  log "  -> base kernel: ${KERNEL_VER}"
  if ! ls /akmods-nvidia-rpms/kmods/kmod-nvidia-"${KERNEL_VER}"-*.rpm >/dev/null 2>&1; then
    echo "install_nvidia_open: no kmod-nvidia RPM matching base image's kernel ${KERNEL_VER}" >&2
    echo "  Available kmod-nvidia RPMs under /akmods-nvidia-rpms/kmods/:" >&2
    ls /akmods-nvidia-rpms/kmods/kmod-nvidia-*.rpm 2>/dev/null | sed 's|^|    |' >&2 || echo "    (none)" >&2
    echo "  Fix: bump AKMODS_NVIDIA_OPEN_TAG (and AKMODS_TAG) in" >&2
    echo "       Containerfile.nvidia-open to a tag whose kernel-version" >&2
    echo "       suffix matches ${KERNEL_VER}, or (if the base image drifted" >&2
    echo "       ahead of ublue's akmods CI) wait for ublue to catch up." >&2
    exit 1
  fi

  # ublue-os-{akmods,nvidia}-addons ship:
  #   ublue-os-akmods-addons  — MOK signing cert + secureboot first-boot unit
  #   ublue-os-nvidia-addons  — /etc/yum.repos.d/negativo17-fedora-nvidia*.repo,
  #                             the Negativo17 mirror that provides
  #                             nvidia-driver-selinux (conditionally required
  #                             by nvidia-kmod-common when
  #                             selinux-policy-targeted is installed, which
  #                             kinoite always has). Without this, dnf5 errors
  #                             with "nothing provides nvidia-driver-selinux".
  # Install both -addons RPMs FIRST — the -nvidia-addons RPM drops the repo
  # files that the main install below relies on to resolve
  # nvidia-driver-selinux.
  dnf5 -y install \
    /akmods-rpms/ublue-os/ublue-os-akmods-addons-*.rpm \
    /akmods-nvidia-rpms/ublue-os/ublue-os-nvidia-addons-*.rpm

  # Enable the repos ublue-os-nvidia-addons just dropped (they ship
  # enabled=0 by default). Two of them matter for the main install:
  #   fedora-nvidia*         — Negativo17 mirror; provides nvidia-driver-
  #                            selinux (the previously-missing conditional
  #                            dep of nvidia-kmod-common) plus userspace
  #                            overrides.
  #   nvidia-container-toolkit — NVIDIA's own repo for the container
  #                            toolkit (needed for `podman
  #                            --device=nvidia.com/gpu=all`); the toolkit
  #                            RPM isn't in Fedora, RPMFusion, or the
  #                            fedora-nvidia repo.
  # Missing either produces "nothing provides nvidia-driver-selinux" or
  # "no match for argument: nvidia-container-toolkit" respectively.
  # Match ublue's nvidia-install.sh single-line enablement.
  #
  # Also disable rpmfusion — its nvidia-driver conflicts with Negativo17's
  # (different SRPM/patchset). enable_repos() installed
  # rpmfusion-nonfree-release earlier for codecs; nothing else in the
  # nvidia-open build path needs it, so this disable is safe.
  dnf5 config-manager setopt "fedora-nvidia*".enabled=1 "nvidia-container-toolkit".enabled=1
  if dnf5 repolist --all 2>/dev/null | grep -q rpmfusion; then
    dnf5 config-manager setopt "rpmfusion*".enabled=0
  fi

  # Main nvidia transaction. kmod + full userspace stack + extras that
  # ublue always installs (egl-wayland for Wayland, libva-nvidia-driver for
  # VA-API, nvidia-container-toolkit for podman GPU passthrough). Single
  # transaction so kmod-nvidia's Requires: nvidia-kmod-common and
  # nvidia-kmod-common's Requires: nvidia-driver-selinux both resolve
  # (the former against the pre-copied nvidia/*.noarch.rpm, the latter
  # against fedora-nvidia we just enabled). Skip i686 (multilib) — kinoite
  # doesn't ship multilib enabled; Steam/Wine users can rpm-ostree install
  # those on their own deploy.
  dnf_install \
    /akmods-nvidia-rpms/kmods/kmod-nvidia-"${KERNEL_VER}"-*.rpm \
    /akmods-nvidia-rpms/nvidia/*.x86_64.rpm \
    /akmods-nvidia-rpms/nvidia/*.noarch.rpm \
    egl-wayland \
    libva-nvidia-driver \
    nvidia-container-toolkit

  # modeset=1 makes DRM the primary driver interface (Wayland requirement);
  # fbdev=1 keeps the console framebuffer on nvidia too (avoids nouveau/
  # efifb flicker before the compositor starts). NVreg_UsePageAttributeTable
  # improves mmap perf; NVreg_PreserveVideoMemoryAllocations survives
  # suspend/resume without lost surfaces. Same defaults ublue-os ships.
  install -Dm0644 /dev/stdin /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia NVreg_UsePageAttributeTable=1 NVreg_PreserveVideoMemoryAllocations=1
options nvidia_drm modeset=1 fbdev=1
EOF

  # Prevent nouveau binding the GPU before nvidia.ko loads. Without this
  # nouveau claims the card first and nvidia refuses to bind.
  install -Dm0644 /dev/stdin /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

  # Include the nvidia modules in the initramfs so the compositor can
  # bring the display up on first boot without waiting for udev module
  # loads. bootc-image-builder regenerates the initramfs during ISO/qcow2
  # build using conf.d in the image, so a drop-in here is enough — no
  # dracut -f at build time (which wouldn't work inside the buildah
  # chroot anyway).
  install -Dm0644 /dev/stdin /etc/dracut.conf.d/nvidia.conf <<'EOF'
add_drivers+=" nvidia nvidia_drm nvidia_modeset nvidia_uvm "
EOF
}

install_lookandfeel_themes() {
  log "install_lookandfeel_themes"
  install -d \
    /usr/share/aurorae/themes \
    /usr/share/color-schemes \
    /usr/share/konsole \
    /usr/share/Kvantum \
    /usr/share/plasma/desktoptheme \
    /usr/share/plasma/look-and-feel
  # Sweet LAF variants (EliverLara/Sweet, GPL-3.0). Same repo, theme per
  # branch — mars and Ambar-Blue. Each branch ships the full KDE asset
  # tree the LAF references: kde/aurorae (window deco), kde/colorschemes,
  # kde/konsole, kde/kvantum (widget style), kde/plasma/desktoptheme,
  # kde/plasma/look-and-feel/Plasma6. We install all of them so the LAF's
  # contents/defaults resolves (otherwise Plasma silently falls back to
  # Breeze for each missing dependent). Sweet-cursors is a SEPARATE repo
  # (EliverLara/Sweet-cursors); the LAF references it but Plasma falls
  # back to the system cursor theme when not present — acceptable; not
  # worth carrying a second repo just for cursors users can install
  # themselves with `nelhua-install-flatpaks`-style scope later.
  # renovate: datasource=git-refs depName=EliverLara/Sweet branch=mars
  local sweet_mars_sha="b057b217c826caaf9bea20245d8f1a6ae410cab4"
  _install_sweet_variant Sweet-Mars "${sweet_mars_sha}"
  # renovate: datasource=git-refs depName=EliverLara/Sweet branch=Ambar-Blue
  local sweet_ambar_blue_sha="df37b2fcc62f68046468c660699193be37221f50"
  _install_sweet_variant Sweet-Ambar-Blue "${sweet_ambar_blue_sha}"
}

_install_sweet_variant() {
  # $1 = LAF name as it appears under kde/plasma/look-and-feel/Plasma6/
  # $2 = git SHA on the branch carrying this variant
  local name="$1" sha="$2"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/sweet.tar.gz" \
    "https://github.com/EliverLara/Sweet/archive/${sha}.tar.gz"
  tar -xzf "${tmp}/sweet.tar.gz" -C "${tmp}"
  local kde="${tmp}/Sweet-${sha}/kde"
  # LAF package (Plasma 6 only — kde/plasma/look-and-feel/${name} on these
  # branches is the Plasma 5 LAF, intentionally skipped).
  cp -r "${kde}/plasma/look-and-feel/Plasma6/${name}" \
    /usr/share/plasma/look-and-feel/
  # Dependent assets referenced by LAF's contents/defaults. Glob-copy
  # because the upstream is inconsistent about case: LAF references
  # "Sweet-mars" (lowercase 'm') for the plasma desktop theme while
  # using "Sweet-Mars" (capital M) for aurorae/colorscheme — and
  # each branch's tree may carry extra variant files. Better to ship
  # the whole subdir than guess the canonical name per asset type.
  cp -r "${kde}/aurorae/themes/${name}"     /usr/share/aurorae/themes/   2>/dev/null || true
  cp -r "${kde}/colorschemes/."             /usr/share/color-schemes/    2>/dev/null || true
  cp -r "${kde}/kvantum/${name}"            /usr/share/Kvantum/          2>/dev/null || true
  for d in "${kde}/plasma/desktoptheme/"*; do
    [[ -d "$d" ]] && cp -r "$d" /usr/share/plasma/desktoptheme/
  done
  cp -r "${kde}/konsole/." /usr/share/konsole/ 2>/dev/null || true
  # Skip kde/sddm/ — Kinoite uses plasma-login-manager, not SDDM, so
  # those theme files would just be dead weight under /usr/share/sddm/.
  rm -rf "${tmp}"
}

install_kwin_effects() {
  log "install_kwin_effects"
  install -d /usr/share/kwin/effects
  _install_burn_my_windows
  _install_kinetic_effects
  _install_geometry_change
  _install_squash_plus
}

_install_burn_my_windows() {
  # Burn-My-Windows (Schneegans, GPL-3.0). v48 ships a bundled tarball
  # `burn_my_windows_kwin6.tar.gz` containing ~20 KWin 6 effect kpackages
  # (Aura Glow, Doom, Energize A/B, Fire, Focus, Glide, Glitch, Hexagon,
  # Incinerate, Pixelate, Pixel Wheel, Pixel Wipe, Portal, RGB Warp,
  # Team Rocket, TV, TV Glitch, Wisps). Drop them ALL into /usr/share/
  # kwin/effects/ — the kdestore curation list named 14 of them but the
  # tarball is all-or-nothing and the bonus effects are ~100 KB each, so
  # ship the whole set instead of cherry-picking. None auto-enable;
  # users pick one per minimize/open/close transition in System Settings.
  # The author also publishes per-effect tarballs as separate release
  # assets, but tracking one bundle pin via github-releases is simpler
  # than 14 individual pins. F44 ships Plasma 6.6.5 → kwin6 is the
  # right tree.
  # renovate: datasource=github-releases depName=Schneegans/Burn-My-Windows
  local tag="v48"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/bmw.tar.gz" \
    "https://github.com/Schneegans/Burn-My-Windows/releases/download/${tag}/burn_my_windows_kwin6.tar.gz"
  tar -xzf "${tmp}/bmw.tar.gz" -C "${tmp}"
  # Tarball layout: kwin6_effect_*/ dirs may sit at the archive root OR
  # inside a single wrapper directory depending on upstream's packaging
  # decisions across releases. Use `find` so a future restructure won't
  # silently turn this into a no-op.
  find "${tmp}" -mindepth 1 -maxdepth 3 -type d -name 'kwin6_effect_*' \
    -exec cp -r {} /usr/share/kwin/effects/ \;
  rm -rf "${tmp}"
}

_install_kinetic_effects() {
  # Kinetic Animations (gurrgur/kwin-effects-kinetic, GPL-3.0). Four
  # effect kpackages at the repo root: kinetic_fadingpopups (Menu Fade),
  # kinetic_maximize (Maximize), kinetic_scale (Open/Close), kinetic_squash
  # (Minimize). Repo has no tagged releases — pin to a main HEAD SHA.
  # P6-targeted per upstream description.
  # renovate: datasource=git-refs depName=gurrgur/kwin-effects-kinetic branch=main
  local sha="93f2c57b0d28dcabbb8cfdae260632d109a0d16d"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/kinetic.tar.gz" \
    "https://github.com/gurrgur/kwin-effects-kinetic/archive/${sha}.tar.gz"
  tar -xzf "${tmp}/kinetic.tar.gz" -C "${tmp}"
  local root="${tmp}/kwin-effects-kinetic-${sha}"
  for d in "${root}"/kinetic_*; do
    [[ -d "$d" ]] && cp -r "$d" /usr/share/kwin/effects/
  done
  rm -rf "${tmp}"
}

_install_geometry_change() {
  # Geometry Change (peterfajdiga, GPL). Single effect kpackage; v1.5
  # release ships `kwin4_effect_geometry_change_1_5.tar.gz` containing
  # one effect dir. Plasma 6 compatible per the v1.5 release notes.
  # renovate: datasource=github-releases depName=peterfajdiga/kwin4_effect_geometry_change
  local tag="v1.5"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/gc.tar.gz" \
    "https://github.com/peterfajdiga/kwin4_effect_geometry_change/releases/download/${tag}/kwin4_effect_geometry_change_1_5.tar.gz"
  tar -xzf "${tmp}/gc.tar.gz" -C "${tmp}"
  find "${tmp}" -mindepth 1 -maxdepth 3 -type d -name 'kwin4_effect_*' \
    -exec cp -r {} /usr/share/kwin/effects/ \;
  rm -rf "${tmp}"
}

_install_squash_plus() {
  # Squash-Plus (Shaurya-Kalia, GPL-3.0). The actively-maintained
  # successor to Squash2 — Squash2's own README points users here and
  # explicitly says "this effect won't see further updates." The original
  # KDE store curation list named Squash2 (1806319); we ship Squash-Plus
  # instead per upstream's explicit recommendation. Same author, same
  # animation shape (modified minimize/unminimize), but kept current
  # against KWin API drift. No releases tagged — pin to main HEAD SHA.
  # The repo root IS the kpackage (metadata.json + contents/), so we
  # install it as /usr/share/kwin/effects/kwin4_effect_squashplus/ to
  # match the Id field in metadata.json.
  # renovate: datasource=git-refs depName=Shaurya-Kalia/Squash-Plus branch=main
  local sha="7a59dccfa1c8137e0504bdf50bafea38c08f1948"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/squash.tar.gz" \
    "https://github.com/Shaurya-Kalia/Squash-Plus/archive/${sha}.tar.gz"
  tar -xzf "${tmp}/squash.tar.gz" -C "${tmp}"
  mv "${tmp}/Squash-Plus-${sha}" /usr/share/kwin/effects/kwin4_effect_squashplus
  rm -rf "${tmp}"
}

install_extras() {
  log "install_extras"
  # gaming
  # steam-devices: udev rules for Steam Controller, Steam Deck controllers,
  # DualShock/DualSense, Xbox One/Series controllers. Required for the
  # flatpak Steam (com.valvesoftware.Steam) we offer in nelhua-install-
  # flatpaks — flatpak sandbox can't write to /usr/lib/udev/rules.d/ so
  # the package ships them in the host image. Steam flatpak shows
  # "Missing permissions for input devices" without this.
  dnf_install gamescope mangohud protontricks steam-devices
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

install_icon_themes() {
  log "install_icon_themes"
  install -d /usr/share/icons
  _install_candy_icons
  _install_beautyline
  _install_tela_circle
}

_install_candy_icons() {
  # candy-icons (EliverLara, GPL-3.0). FollowsColorScheme=true so the set
  # auto-tracks BreezeDark vs BreezeLight without a separate dark variant —
  # one install covers light/dark users. Pinned to a SHA so Renovate (or a
  # manual bump) has a single source of truth and reproducibility holds.
  # renovate: datasource=git-refs depName=EliverLara/candy-icons branch=master
  local sha="83512fbcadcb7e1015ebbe1729a1894946b021be"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/candy.tar.gz" \
    "https://github.com/EliverLara/candy-icons/archive/${sha}.tar.gz"
  tar -xzf "${tmp}/candy.tar.gz" -C "${tmp}"
  mv "${tmp}/candy-icons-${sha}" /usr/share/icons/candy-icons
  rm -rf "${tmp}"
  gtk-update-icon-cache -f /usr/share/icons/candy-icons 2>/dev/null || true
}

_install_beautyline() {
  # BeautyLine (Garuda Linux fork on GitLab, GPL-3.0 — see COPYING in
  # source tree). Original store.kde.org author (1425426) has no public
  # repo; gvolpe/BeautyLine on GitHub is stale (7 commits, last release
  # Jan 2022 + a multi-version subdir layout that's not drop-in). Garuda's
  # fork is actively tagged (3.0.x line, tagged Nov 2025) and the repo
  # root IS the icon theme dir (index.theme + apps/devices/places/etc).
  # GitLab tag pin → tracked by the gitlab-tags custom manager in
  # renovate.json5.
  # renovate: datasource=gitlab-tags depName=garuda-linux/themes-and-settings/artwork/beautyline
  local tag="3.0.3"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/beautyline.tar.gz" \
    "https://gitlab.com/garuda-linux/themes-and-settings/artwork/beautyline/-/archive/${tag}/beautyline-${tag}.tar.gz"
  tar -xzf "${tmp}/beautyline.tar.gz" -C "${tmp}"
  mv "${tmp}/beautyline-${tag}" /usr/share/icons/BeautyLine
  rm -rf "${tmp}"
  gtk-update-icon-cache -f /usr/share/icons/BeautyLine 2>/dev/null || true
}

_install_tela_circle() {
  # Tela-circle (vinceliuice, GPL-3.0). 915 stars, regular releases — the
  # well-maintained option of the bunch. Unlike candy/BeautyLine the repo
  # is NOT a drop-in theme dir; source variants live in src/ and install.sh
  # generates the per-color theme tree at the chosen install root. With no
  # args, install.sh ships ONE variant ("standard") to /usr/share/icons/
  # Tela-circle when run as root — the right minimum for a "Tela circle is
  # available" image. Users who want other colors (15 available: black,
  # blue, brown, purple, etc.) can re-run install.sh from a clone with
  # their pick.
  # renovate: datasource=git-refs depName=vinceliuice/Tela-circle-icon-theme branch=master
  local sha="e3171a34427d0900046dedbdf9979631adea7608"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/tela.tar.gz" \
    "https://github.com/vinceliuice/Tela-circle-icon-theme/archive/${sha}.tar.gz"
  tar -xzf "${tmp}/tela.tar.gz" -C "${tmp}"
  ( cd "${tmp}/Tela-circle-icon-theme-${sha}" && ./install.sh )
  rm -rf "${tmp}"
  # install.sh runs gtk-update-icon-cache itself; no second call needed.
}

install_superfile() {
  log "install_superfile"
  if [[ -x /usr/bin/spf ]]; then
    return 0
  fi
  local arch tmp archive binary
  # Pinned to avoid the unauthenticated api.github.com/repos/.../releases/latest
  # call we used to make here — that endpoint is rate-limited to 60/hr per IP
  # and CI runners share egress pools, so a bad neighbor's traffic would 403
  # this step. Renovate keeps the pin fresh.
  # renovate: datasource=github-releases depName=yorukot/superfile
  local tag="v1.6.0"
  case "$(uname -m)" in
    x86_64)  arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo "Unsupported arch: $(uname -m)" >&2; return 1 ;;
  esac
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
  # Both setup units are oneshot, guarded by ConditionPathExists so they run
  # exactly once per fresh deployment. Units live in
  # files/system/etc/systemd/system/ and were just rsync'd in by apply_files.
  systemctl enable brew-setup.service
  systemctl enable nix-setup.service
  # Auto-update: daily fetch, stage on disk, user reboots when ready.
  # Shipped (but not enabled) by the upstream bootc package; we enable here.
  # Matches the ublue pattern (Bluefin/Bazzite/Aurora ship this enabled).
  systemctl enable bootc-fetch-apply-updates.timer
  # fwupd LVFS metadata refresh — belt-and-suspenders enable in case the
  # Fedora preset isn't carried forward by fedora-bootc. Kinoite has it
  # preset-on; Aurora relies on that and doesn't enable explicitly.
  systemctl enable fwupd-refresh.timer
  # Weekly Nix store GC. Guarded by ConditionPathExists on the nix daemon
  # binary; no-op until Determinate Nix has actually been installed.
  systemctl enable nix-gc.timer
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
# ostree-image-signed: refuses to operate when the policy default is
# insecureAcceptAnything ("anything could slip through unverified;
# refusing usage"). Flip default to reject and add a docker."" catch-all
# back as insecureAcceptAnything so non-nelhua registry pulls behave as
# they did before. Net effect: identical for everything except this
# image, which is now signed-only.
data['default'] = [{'type': 'reject'}]
data.setdefault('transports', {}).setdefault('docker', {}).setdefault(
    '', [{'type': 'insecureAcceptAnything'}]
)
# Also allow the containers-storage: transport. bootc install-to-filesystem
# (invoked by bootc-image-builder at qcow2 build time) opens the source
# image via a containers-storage: URI, and without an explicit entry it
# falls through to default:reject — every qcow2 disk build then errors
# with "containers-storage:... is rejected by policy." Local storage is
# already trusted by the time an image is on disk; signature verification
# is a docker:-transport concern at fetch time. anaconda-iso doesn't hit
# this because bootc install-to-filesystem runs at install time on the
# target, not at build time on the runner.
data['transports'].setdefault('containers-storage', {}).setdefault(
    '', [{'type': 'insecureAcceptAnything'}]
)
data['transports']['docker']['${IMAGE_REGISTRY_PATH}'] = [{
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
    mango)                pretty="Nelhua-Linux (Mango Edition)" ;;
    kde)                  pretty="Nelhua-Linux (KDE)" ;;
    kinectic)             pretty="Nelhua-Linux (KineticWE)" ;;
    kde-nvidia-open)      pretty="Nelhua-Linux (KDE + NVIDIA open)" ;;
    kinectic-nvidia-open) pretty="Nelhua-Linux (KineticWE + NVIDIA open)" ;;
    *)                    pretty="Nelhua-Linux" ;;
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
  dnf5 -y copr disable ama1470/kwin-effects-glass || true
  dnf5 clean all
  # Comprehensive scrub: build-time state in /var that won't survive the
  # first-boot reset, plus runtime-only paths that bootc lint flags
  # (nonempty-run-tmp).
  rm -rf /var/cache/* /var/log/* /tmp/* /var/tmp/*
  rm -rf /run/* 2>/dev/null || true
}

install_desktop() {
  case "$DESKTOP" in
    mango)                install_desktop_mango ;;
    kde)                  install_desktop_kde ;;
    kinectic)             install_desktop_kinectic ;;
    kde-nvidia-open)      install_desktop_kde;      install_nvidia_open ;;
    kinectic-nvidia-open) install_desktop_kinectic; install_nvidia_open ;;
    *) echo "Unknown DESKTOP='$DESKTOP' (expected mango|kde|kinectic|kde-nvidia-open|kinectic-nvidia-open)" >&2; exit 1 ;;
  esac
}

main() {
  log "build (desktop=${DESKTOP}, image=${IMAGE_NAME}, base=$(. /etc/os-release && echo "${PRETTY_NAME}"))"
  enable_repos
  install_base
  install_hardware
  install_desktop      # dispatches to install_desktop_{mango,kde,kinectic}; *-nvidia-open flavors chain install_nvidia_open after their base install
  install_extras
  install_icon_themes
  install_superfile
  apply_files          # ship system tree (including brew-setup + nix-setup units)
  setup_plymouth       # MUST be after apply_files — needs /usr/share/plymouth/themes/nelhua on disk
  enable_first_boot_services
  remove_unwanted
  apply_signing
  apply_os_release
  cleanup_var_state    # scrub /var/lib state (dnf cache, plocate, etc.)
  generate_var_tmpfiles # emit tmpfiles.d for surviving /var/lib dirs + symlinks
  cleanup              # final pass: cache/log/tmp/run
}

main "$@"
