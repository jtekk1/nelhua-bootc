# nelhua-bootc

[![Build](https://github.com/jtekk1/nelhua-bootc/actions/workflows/build.yml/badge.svg)](https://github.com/jtekk1/nelhua-bootc/actions/workflows/build.yml)
[![Build disk](https://github.com/jtekk1/nelhua-bootc/actions/workflows/build-disk.yml/badge.svg)](https://github.com/jtekk1/nelhua-bootc/actions/workflows/build-disk.yml)
[![Latest release](https://img.shields.io/github/v/tag/jtekk1/nelhua-bootc?label=latest%20release&color=blue)](https://github.com/jtekk1/nelhua-bootc/tags)
[![Renovate](https://img.shields.io/badge/Renovate-enabled-1A1F6C?logo=renovatebot&logoColor=white)](https://docs.renovatebot.com/)

Personal Fedora-based [bootc](https://github.com/bootc-dev/bootc) images. One source tree builds four desktop variants (mango Wayland WM, KDE Plasma, KineticWE — a tiling KWin fork, or KDE Plasma + NVIDIA open kernel modules), each off a stable Fedora release or rawhide, signed with cosign, distributed via ghcr.io.

## Images shipped

| Image | Desktop | Base | Channels (OCI tags) |
|---|---|---|---|
| `ghcr.io/jtekk1/nelhua-mango` | [Mango](https://github.com/DreamMaoMao/mango) Wayland compositor | `quay.io/fedora/fedora-bootc:44` | ⚠️ CI paused — last published tags remain valid |
| `ghcr.io/jtekk1/nelhua-kde` | KDE Plasma 6 | `quay.io/fedora/fedora-kinoite:44` | `:latest`, `:stable`, `:v<tag>`, dated `:<channel>.YYYYMMDD` |
| `ghcr.io/jtekk1/nelhua-kinectic` | KDE Plasma 6 with [KineticWE](https://gitlab.com/theblackdon/kineticwe) — tiling KWin fork swapping the stock compositor | `quay.io/fedora/fedora-kinoite:44` | `:latest`, `:stable`, `:v<tag>`, dated `:<channel>.YYYYMMDD` |
| `ghcr.io/jtekk1/nelhua-kde-nvidia-open` | KDE Plasma 6 + NVIDIA **open kernel modules** driver (Turing+ / RTX 20-series and newer) | `quay.io/fedora/fedora-kinoite:44` | `:latest`, `:stable`, `:v<tag>`, dated `:<channel>.YYYYMMDD` |

- **mango**: CI is paused because Terra F44 currently doesn't publish `libscenefx-0.4.so`, so `mangowm` can't be resolved. `install_desktop_mango()` and `./build.sh mango` still work locally — CI re-enables the flavor once Terra restores scenefx.
- **kde-nvidia-open**: bundles NVIDIA's **open kernel modules** driver stream (open source kernel modules, closed userspace). Works on Turing+ / RTX 20-series / GTX 16-series and newer; older cards need the proprietary driver, which we don't yet ship. Kernel modules are pre-built and signed by [ublue-os/akmods](https://github.com/ublue-os/akmods) against exactly the kernel our kinoite base ships (matched by tag pins in `Containerfile.nvidia-open` — Renovate keeps them in step with the base kernel). On Secure Boot systems, ublue's MOK cert is enrolled at first boot via `ublue-os-akmods-secureboot.service` (you'll see the shim MOK enrollment prompt at your first reboot after install).
- **rawhide channel**: temporarily disabled across all flavors — `apply_signing()` assumes `/etc/containers/policy.json` exists on the base, which F45 kinoite no longer ships. Fix pending; see `plan.md`.

Channel semantics:

| Tag | Updates when |
|---|---|
| `:latest` | every push to `main` (+ daily cron catch-up at 10:05 UTC) |
| `:stable` | manual `workflow_dispatch` or pushing a `v*` git tag |
| `:v<tag>` | pushing a `v*` git tag — immutable release pin |
| `:rawhide` | temporarily disabled — see paused-rawhide note above |
| `:<channel>.YYYYMMDD` | dated variant of each, auto-pruned by ghcr.io retention |
| `:pr-<N>` / `:rawhide-pr-<N>` | PR builds — built and signed but **not pushed** |

`:latest` is always at tip-of-main; `:stable` advances only on deliberate cuts.

## Switching an existing bootc system to one of these

```bash
# Mango (Wayland WM)
sudo bootc switch ghcr.io/jtekk1/nelhua-mango:stable

# KDE Plasma
sudo bootc switch ghcr.io/jtekk1/nelhua-kde:stable

# KineticWE (KDE Plasma + tiling KWin fork)
sudo bootc switch ghcr.io/jtekk1/nelhua-kinectic:stable

# KDE Plasma + NVIDIA open kernel modules (Turing+ hardware)
sudo bootc switch ghcr.io/jtekk1/nelhua-kde-nvidia-open:stable

sudo systemctl reboot
```

Use `:latest` to follow tip-of-main, `:stable` for the deliberate channel. (`:rawhide` is temporarily unbuilt — see status notes above.)

## Repo layout

- `Containerfile` — parameterized by `BASE_IMAGE`, `IMAGE_NAME`, `DESKTOP` build args. Single `RUN` invokes `build_files/build.sh` with build context bind-mounted at `/ctx` and the `files/system/` tree at `/system-files`. Used by mango, kde, kinectic.
- `Containerfile.nvidia-open` — variant used by the `kde-nvidia-open` flavor. Adds two `FROM ghcr.io/ublue-os/akmods*` stages and mounts their `/rpms/` trees on the main `RUN` so `install_nvidia_open()` can dnf-install pre-built kmods + userspace + cert enrollment. Kernel-lock invariant is documented at the top of the file.
- `build_files/build.sh` — all image customization. `install_desktop` dispatches to `install_desktop_{mango,kde,kinectic}` based on the `DESKTOP` env (set from the build arg); `kde-nvidia-open` runs `install_desktop_kde` then `install_nvidia_open`.
- `files/system/` — overlay rsync'd into the image rootfs at the end of `build.sh` (systemd unit files, udev rules, dracut configs, fontconfig, iwd config, etc.).
- `files/dnf/` — repo definition files (`terra.repo`) copied into `/etc/yum.repos.d/` by `build.sh`.
- `disk_config/` — [bootc-image-builder](https://github.com/osbuild/bootc-image-builder) configs for qcow2 (`disk.toml`) and ISO (`iso-{kde,kinectic,kde-nvidia-open}.toml`).
- `.github/workflows/build.yml` — 2D matrix (`desktop × channel` = 3 cells per trigger currently: kde/stable, kinectic/stable, kde-nvidia-open/stable; mango + rawhide temporarily disabled — see README status notes), buildah → ghcr.io → cosign sign. Per-flavor `containerfile:` field selects `./Containerfile` vs `./Containerfile.nvidia-open`.
- `.github/workflows/build-disk.yml` — manual workflow that builds qcow2 + ISO from a published tag via bootc-image-builder.
- `cosign.pub` — signing pubkey baked into the image so the deployed system verifies signatures.
- `plan.md` — design notes and open items.

## Local build

```bash
./build.sh                          # mango           -> nelhua-mango:latest    (default)
./build.sh kde                      # KDE             -> nelhua-kde:latest
./build.sh kde dev                  # KDE             -> nelhua-kde:dev
./build.sh kinectic                 # KineticWE       -> nelhua-kinectic:latest
./build.sh kde-nvidia-open          # KDE + NVIDIA    -> nelhua-kde-nvidia-open:latest

./build-qcow2.sh kde                # bootc-image-builder -> output/qcow2/disk.qcow2
./build-iso.sh kde                  # bootc-image-builder -> output/bootiso/install.iso
TYPE=qcow2 ./run-vm.sh kde          # boot the qcow2 via systemd-vmspawn (qemu fallback)
TYPE=iso  ./run-vm.sh kde           # boot the install ISO
```

Omit the desktop arg to get mango (default). All scripts also accept `IMAGE_NAME`, `TAG`, `BIB_IMAGE` env overrides.

`build-qcow2.sh` and `build-iso.sh` run `bootc-image-builder` under `sudo podman`. The first time you run them after a fresh build, they auto-copy the image from rootless to rootful podman storage (BIB needs to see it under sudo).

## Verifying signatures

```bash
cosign verify --key cosign.pub ghcr.io/jtekk1/nelhua-mango:stable
cosign verify --key cosign.pub ghcr.io/jtekk1/nelhua-kde:stable
cosign verify --key cosign.pub ghcr.io/jtekk1/nelhua-kinectic:stable
cosign verify --key cosign.pub ghcr.io/jtekk1/nelhua-kde-nvidia-open:stable
```

Each image bakes its own policy entry into `/etc/containers/policy.json` and `/etc/containers/registries.d/<image>.yaml`, so once deployed the signing key is enforced for subsequent upgrades.
