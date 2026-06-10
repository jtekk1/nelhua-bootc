# nelhua-bootc

[![Build](https://github.com/jtekk1/nelhua-bootc/actions/workflows/build.yml/badge.svg)](https://github.com/jtekk1/nelhua-bootc/actions/workflows/build.yml)
[![Build disk](https://github.com/jtekk1/nelhua-bootc/actions/workflows/build-disk.yml/badge.svg)](https://github.com/jtekk1/nelhua-bootc/actions/workflows/build-disk.yml)
[![Latest release](https://img.shields.io/github/v/tag/jtekk1/nelhua-bootc?label=latest%20release&color=blue)](https://github.com/jtekk1/nelhua-bootc/tags)
[![Renovate](https://img.shields.io/badge/Renovate-enabled-1A1F6C?logo=renovatebot&logoColor=white)](https://docs.renovatebot.com/)

Personal Fedora-based [bootc](https://github.com/bootc-dev/bootc) images. One source tree builds two desktop variants (mango Wayland WM or KDE Plasma), each off a stable Fedora release or rawhide, signed with cosign, distributed via ghcr.io.

## Images shipped

| Image | Desktop | Base | Channels (OCI tags) |
|---|---|---|---|
| `ghcr.io/jtekk1/nelhua-mango` | [Mango](https://github.com/DreamMaoMao/mango) Wayland compositor | `quay.io/fedora/fedora-bootc:44` (stable) / `:rawhide` | `:latest`, `:stable`, `:rawhide`, `:v<tag>`, dated `:<channel>.YYYYMMDD` |
| `ghcr.io/jtekk1/nelhua-kde` | KDE Plasma 6 | `quay.io/fedora/fedora-kinoite:44` (stable) / `:rawhide` | `:latest`, `:stable`, `:rawhide`, `:v<tag>`, dated `:<channel>.YYYYMMDD` |

Channel semantics:

| Tag | Updates when |
|---|---|
| `:latest` | every push to `main` (+ daily cron catch-up at 10:05 UTC) |
| `:stable` | manual `workflow_dispatch` or pushing a `v*` git tag |
| `:v<tag>` | pushing a `v*` git tag — immutable release pin |
| `:rawhide` | every non-PR trigger; built best-effort against Fedora rawhide |
| `:<channel>.YYYYMMDD` | dated variant of each, auto-pruned by ghcr.io retention |
| `:pr-<N>` / `:rawhide-pr-<N>` | PR builds — built and signed but **not pushed** |

`:latest` is always at tip-of-main; `:stable` advances only on deliberate cuts.

## Switching an existing bootc system to one of these

```bash
# Mango (Wayland WM)
sudo bootc switch ghcr.io/jtekk1/nelhua-mango:stable

# KDE Plasma
sudo bootc switch ghcr.io/jtekk1/nelhua-kde:stable

sudo systemctl reboot
```

Use `:latest` to follow tip-of-main, `:stable` for the deliberate channel, `:rawhide` if you want Fedora rawhide and accept the breakage that implies.

## Repo layout

- `Containerfile` — parameterized by `BASE_IMAGE`, `IMAGE_NAME`, `DESKTOP` build args. Single `RUN` invokes `build_files/build.sh` with build context bind-mounted at `/ctx` and the `files/system/` tree at `/system-files`.
- `build_files/build.sh` — all image customization. `install_desktop` dispatches to `install_desktop_mango` or `install_desktop_kde` based on the `DESKTOP` env (set from the build arg).
- `files/system/` — overlay rsync'd into the image rootfs at the end of `build.sh` (systemd unit files, udev rules, dracut configs, fontconfig, iwd config, etc.).
- `files/dnf/` — repo definition files (`terra.repo`) copied into `/etc/yum.repos.d/` by `build.sh`.
- `disk_config/` — [bootc-image-builder](https://github.com/osbuild/bootc-image-builder) configs for qcow2 (`disk.toml`) and ISO (`iso.toml`).
- `.github/workflows/build.yml` — 2D matrix (`desktop × channel` = 4 cells per trigger), buildah → ghcr.io → cosign sign.
- `.github/workflows/build-disk.yml` — manual workflow that builds qcow2 + ISO from a published tag via bootc-image-builder.
- `cosign.pub` — signing pubkey baked into the image so the deployed system verifies signatures.
- `archive/bluebuild-kde/` — historical BlueBuild-era KDE recipe, preserved for reference.
- `plan.md` — design notes and open items.

## Local build

```bash
./build.sh                     # mango -> nelhua-mango:latest (default)
./build.sh kde                 # KDE   -> nelhua-kde:latest
./build.sh kde dev             # KDE   -> nelhua-kde:dev

./build-qcow2.sh kde           # bootc-image-builder -> output/qcow2/disk.qcow2
./build-iso.sh kde             # bootc-image-builder -> output/bootiso/install.iso
TYPE=qcow2 ./run-vm.sh kde     # boot the qcow2 via systemd-vmspawn (qemu fallback)
TYPE=iso  ./run-vm.sh kde      # boot the install ISO
```

Omit the desktop arg to get mango (default). All scripts also accept `IMAGE_NAME`, `TAG`, `BIB_IMAGE` env overrides.

`build-qcow2.sh` and `build-iso.sh` run `bootc-image-builder` under `sudo podman`. The first time you run them after a fresh build, they auto-copy the image from rootless to rootful podman storage (BIB needs to see it under sudo).

## Verifying signatures

```bash
cosign verify --key cosign.pub ghcr.io/jtekk1/nelhua-mango:stable
cosign verify --key cosign.pub ghcr.io/jtekk1/nelhua-kde:stable
```

Each image bakes its own policy entry into `/etc/containers/policy.json` and `/etc/containers/registries.d/<image>.yaml`, so once deployed the signing key is enforced for subsequent upgrades.
