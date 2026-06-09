# Open items

## [P1] WiFi: disassociation every ~7 minutes (diagnosed 2026-06-09)

**Original symptom:** on WiFi, the machine got a new IP every ~7 minutes.

**Actual cause:** not DHCP renewal. iwd was **disassociating from the AP every ~7 minutes** and re-associating; the new DHCP lease was a side effect of the link going down and back up. Confirmed via `journalctl -u iwd --since '1 hour ago' | grep state` showing repeated `connected → disconnected → autoconnect → connected` cycles at almost exactly 6:56–7:00 intervals.

**Root cause:** the wifi chipset is a **Realtek RTL8922AE (`rtw89_8922ae` driver)**. rtw89 does not support proper off-channel background scanning, so iwd's default periodic scan (used to look for better APs to roam to) interrupts the active association. The scan completes, iwd reconnects, fresh DHCP. Repeat every 7 minutes.

**Fix (live-confirmed 2026-06-09):** add `[Scan] DisablePeriodicScan=true` to `/etc/iwd/main.conf`. Shipped in `files/system/etc/iwd/main.conf` so every install gets it. Verified on the daily driver — 12+ minutes with zero `connected → disconnected` events after applying, vs. the prior every-7-min cadence. Next image bake includes it; users on existing deployments can drop the same config in `/etc/iwd/main.conf` and `systemctl restart iwd`.

**Live test on a machine experiencing the issue:**
```bash
sudo tee /etc/iwd/main.conf > /dev/null <<'EOF'
[General]
EnableNetworkConfiguration=true

[Scan]
DisablePeriodicScan=true
EOF
sudo systemctl restart iwd
journalctl -u iwd -f   # watch for 15+ minutes; no disconnect = fix confirmed
```

**Escalation paths if the scan-disable doesn't hold:**
- rtw89 + iwd is a known troublesome combo. If disconnects persist, fall back to **NetworkManager + wpa_supplicant** (the path 95% of distros use). Requires: add `wpa_supplicant` to `build.sh`, drop `EnableNetworkConfiguration=true` from iwd, recreate the wifi profile under NM.
- Or: NM + iwd backend (`[device] wifi.backend=iwd` in `/etc/NetworkManager/conf.d/`). NM owns DHCP and profile; iwd owns association. Eliminates iwd autonomous mode without abandoning iwd entirely.

**Other open sub-questions:**
- iwd's known-networks dir `/var/lib/iwd/` appeared empty (even with sudo) on the daily driver, yet iwd autoconnects on boot. Worth confirming where credentials actually live on this system — bootc/ostree may have moved or shadowed the path.
- Confirm the fix on third-party hardware (different chipsets) doesn't *introduce* new issues — DisablePeriodicScan does mean no auto-roam to better APs.

## First-boot: mango doesn't exit cleanly after first-boot setup

**Symptom:** after the post-install first-boot setup script finishes, mango doesn't quit. User is left staring at a black screen with no way to log in cleanly. They have to power-cycle or switch VT, then log in via greetd — but settings configured by first-boot may not have been picked up by the resulting session.

**What we want:** the first-boot setup script, at completion, kills the mango session so the user is dropped back at tui-greet. Login from there starts a fresh mango session with the new settings applied.

**Where to fix:**
- `files/system/usr/libexec/nelhua/first-boot-setup` (the wizard) — at end-of-script, `pkill -KILL mango` (or `pkill -KILL -u "$USER" mango`)
- Verify the post-mango cleanup leaves the seat in a state greetd can re-attach to. May need to `loginctl terminate-session "$XDG_SESSION_ID"` instead of, or in addition to, killing mango directly
- Consider whether this is "first-boot only" (gated by the brew-setup-style ConditionPathExists pattern) or unconditional

**Combine with `dialog -> gum` migration:** the `dialog → gum` rewrite (existing open item below) is the natural moment to also fix this — the script gets a complete rewrite, the exit-cleanly logic gets put in at the same time.

## Branding overhaul (installer ISO + boot splash)

### Installer ISO branding

**Goal:** the installer ISO currently shows generic Fedora branding (welcome screen, logo, boot splash) inherited from anaconda's templates. Replace with Nelhua branding.

**Where it comes from now:**
- ISO generation is via `bootc-image-builder` per `disk_config/iso.toml`
- BIB delegates to anaconda + lorax under the hood; branding is still sourced from the `fedora-logos` rpm plus anaconda product config
- The previous BlueBuild flow used `jasonn3/build-container-installer` and the `--variant server` knob; that's gone with the BIB migration

**Options ranked by effort:**
1. **Override the product string only** — `bootc-image-builder` may expose a way to set the anaconda product name without replacing logos. Investigate the BIB config schema before committing.
2. **Ship a `nelhua-logos` rpm** — small rpm placing PNGs in `/usr/share/anaconda/pixmaps/` plus a `product.d/nelhua.conf`. Install it via `build.sh`. The pixmaps would also cover the installed-system boot splash if we ship them under `/usr/share/plymouth/themes/nelhua/`.
3. **Post-process the built ISO** — extract, swap branding files, repack. Brittle; breaks on upstream changes.

Recommended path: option 2. Build a `nelhua-logos` rpm and pull it in via `build.sh`'s `apply_files()` step or a direct `dnf install` against a private repo.

### Boot splash

**Symptom (pre-migration):** at boot, the BlueBuild logo appeared during plymouth's phase.

**State after migration:**
- `setup_plymouth()` in `build_files/build.sh` installs `plymouth-theme-solar` and calls `plymouth-set-default-theme solar`
- The original `dracut -f --regenerate-all` call has been removed — that's not how initramfs gets regenerated in a bootc flow. Initramfs build happens in BIB or on the deployed system, not the container build.
- If `solar` still doesn't apply after this change, the override is happening elsewhere — either the base image ships a `default.plymouth` symlink that wins, or BIB's initramfs build path doesn't pick up the theme

**Diagnostic step on a built image:**
- `plymouth-set-default-theme --list` (what's installed)
- `plymouth-set-default-theme` (what's currently active)
- `grep -r theme /etc/plymouth/ /usr/share/plymouth/themes/default.plymouth 2>/dev/null`
- `journalctl -b | grep -i plymouth | head`

**If solar doesn't stick, options:**
1. Build a `nelhua-plymouth-theme` (own `.plymouth` + frames under `files/system/usr/share/plymouth/themes/nelhua/`) and set it as default in `setup_plymouth()`. Most polished result.
2. Hunt down what's overriding `solar` and fix that (likely the base image's `/etc/plymouth/plymouthd.conf` or a `default.plymouth` symlink the `apply_files` step doesn't replace).

## Anaconda reboot-hang investigation

**Symptom (pre-migration):** after install completes and the user clicks "Reboot" in anaconda, the screen goes gray and stays gray until power-button reset.

**Status:** unknown under the new BIB-based ISO flow. The previous root-cause hypothesis (an anaconda inhibitor or framebuffer reset bug) may or may not reproduce — BIB uses a slightly different anaconda chain than `jasonn3/build-container-installer`.

**Re-test plan:**
1. Build a fresh ISO with `./build-iso.sh`.
2. Install in a VM; click Reboot.
3. If the gray-screen returns, press **Ctrl+Alt+F2** to drop to a console — that distinguishes "GUI wedged" from "shutdown actually hung."
4. If the bug reproduces and is anaconda's fault, add kernel args at install-boot via `disk_config/iso.toml`'s `[customizations.kernel] append = "..."` block (e.g., `plymouth.enable=0 console=tty1 inst.nokill`). This is the knob BlueBuild's `generate-iso` couldn't pass through; BIB exposes it natively.

## Migrate first-boot wizard from `dialog` to `gum`

**Goal:** the first-boot wizard at `files/system/usr/libexec/nelhua/first-boot-setup` uses `dialog`. Replace with [`gum`](https://github.com/charmbracelet/gum) for a modern styled TUI.

**Affected files:**
- `files/system/usr/libexec/nelhua/first-boot-setup` — rewrite each step: `dialog --yesno` → `gum confirm`; `dialog --checklist` → `gum choose --no-limit`; `dialog --msgbox` → `gum format` or `gum spin`
- `build_files/build.sh` — replace `dialog` with `gum` in the `install_base()` package list (or keep both during transition)

**Notes:**
- `gum` is in Fedora repos; no extra repo needed
- gum returns values on stdout — no `3>&1 1>&2 2>&3` redirection dance
- gum doesn't have a single full-screen "dialog" abstraction; each prompt is its own command. The kitty-fullscreen wrapper still works
- Wrap the long-running `flatpak install` step in `gum spin` for nicer progress

## agetty autologin on tty1 (not shipped)

The old `~/Projects/fedora/post-install/agetty-autologin-tty1/conf` autologs `jtekk` on tty1. Hardcoded username makes it unsuitable for a multi-tenant image. Possible answers:
- Drop it entirely — most users won't want tty1 autologin
- Make it configurable: a small dropin that reads `/etc/nelhua/autologin` for the username, falls back to no autologin if empty/absent
- Add as a knob to the first-boot wizard ("auto-login at console?")

Skip for now; revisit if a real use case emerges.

## ZSA keyboard: user-to-plugdev membership

`50-zsa.rules` is shipped, and `groupadd -r plugdev` runs at build time. But users created at install time are NOT in `plugdev`, so ZSA flashing (Wally/Keymapp) won't work until the user is added manually:
```
sudo usermod -aG plugdev "$USER"
```
Long-term: have the first-boot wizard offer "you have a ZSA keyboard?" and gate the group-add behind that.

## Add Nix as a package manager

**Goal:** ship Nix alongside the existing user-level package managers (Flatpak, Homebrew, Distrobox) so CLI tooling and reproducible per-project environments are available without layering rpms.

**Why now:** brew is fine for ad-hoc CLI installs but doesn't model reproducibility. Nix gives both — `nix profile install` for ad-hoc and `flake.nix` / `direnv` for project-local pinned envs. With `direnv` already in the image, the Nix story slots in cleanly.

**Bootstrap pattern (mirroring brew):**
- The existing `brew-setup.service` is a oneshot guarded by `ConditionPathExists=!/home/linuxbrew/.linuxbrew/bin/brew` that runs `setup-brew.sh` on first boot. Adopt the same shape:
  - `files/system/etc/systemd/system/nix-setup.service` — oneshot, `ConditionPathExists=!/nix/var/nix/profiles/default/bin/nix`
  - `files/system/usr/libexec/blue-mango/setup-nix.sh` — the actual installer invocation
  - `build_files/build.sh` `enable_brew_setup` extends to `enable_first_boot_services` and enables both units
- Pre-create `/nix` as a real directory at build time (not a symlink). bootc/ostree treats `/` as read-only post-deploy except for known paths; `/nix` needs to be writable and ideally on its own mount or a writable subvolume. This is the load-bearing detail — without it, the installer fails.

**Which Nix installer:**
- **Determinate Systems' installer** (`curl -L https://install.determinate.systems/nix | sh -s -- install --determinate`) — handles SELinux-enforcing systems, atomic distros, and immutable rootfs better than the official installer. Recommended starting point.
- Official multi-user installer is the fallback if we don't want Determinate's daemon.

**Open sub-questions:**
- Where does `/nix` live? Options: dedicated subvolume (clean, requires installer to provision), bind-mount of `/var/lib/nix-store` (works without partitioning), or first-boot `mkdir -p /nix` + the installer puts everything there (simplest).
- Channel/flake defaults? Ship a default `~/.config/nix/nix.conf` enabling `experimental-features = nix-command flakes`? Or leave fully unopinionated?
- Auto-add a default Nix channel during setup, or let the user pick?
- Do we want `nixpkgs` mirror configured to a fast/local source (`forgejo.jtekk.dev`?) or default upstream?

**Coordination with stage1 (Jaguar):** Jaguar's PRD currently lists Flatpak + Distrobox + Homebrew as the user-level managers. If Nix proves out in stage0, propose adding it to the Jaguar plan at promotion time.

## Browser strategy refinement

The image currently ships `chromium` and `helium-browser` from dnf, with Firefox removed in `remove_unwanted()`. The longer-term direction is a first-boot picker that installs a chosen browser as a Flatpak (per Jaguar's planned UX). For stage0, the dnf-installed pair is acceptable; revisit once the first-boot wizard is on `gum` and can host the picker UX.
