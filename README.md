# nelhua-linux-bootc (mango edition)

A personal Fedora-based [bootc](https://github.com/bootc-dev/bootc) image with the [Mango](https://github.com/DreamMaoMao/mango) Wayland compositor as the desktop. This is **stage0** of Nelhua Linux — a shippable prototype that the eventual Jaguar/BuildStream-based distro will evolve out of.

## What's here

- `Containerfile` — base image is `quay.io/fedora/fedora-bootc:44`. Single `RUN` invokes `build_files/build.sh` with build context bind-mounted at `/ctx` and the `files/system` tree mounted at `/system-files`.
- `build_files/build.sh` — all image customization: repos, packages, hardware drivers, plymouth, mango, brew bootstrap, signing policy, branding.
- `files/system/` — overlay copied into the image rootfs at the end of `build.sh`.
- `files/dnf/` — repo definition files (`terra.repo`) copied into `/etc/yum.repos.d/` by `build.sh`.
- `disk_config/` — [bootc-image-builder](https://github.com/osbuild/bootc-image-builder) configs for qcow2 (`disk.toml`) and ISO (`iso.toml`).
- `.github/workflows/build.yml` — builds, pushes, and cosign-signs on schedule / push / PR / manual dispatch. Cron writes `:latest`, push-to-main and manual dispatch write `:stable`, PRs build but don't push.
- `.github/workflows/build-disk.yml` — manual workflow that builds qcow2 + ISO from a published tag via bootc-image-builder.
- `cosign.pub` — signing pubkey baked into the image so the deployed system verifies signatures.
- `archive/bluebuild-kde/` — the previous KDE BlueBuild recipe, preserved for reference if KDE work resumes.
- `plan.md` — design notes and open items.

## Local build

```bash
./build.sh                  # podman build -> nelhua-mango:latest
./build-qcow2.sh            # bootc-image-builder -> output/qcow2/disk.qcow2
./build-iso.sh              # bootc-image-builder -> output/bootiso/install.iso
TYPE=qcow2 ./run-vm.sh      # boot the qcow2 via systemd-vmspawn (or qemu fallback)
TYPE=iso ./run-vm.sh        # boot the install ISO
```

`build-qcow2.sh` and `build-iso.sh` run `bootc-image-builder` under `sudo podman` against the locally built image.

## Switching an existing bootc system to this image

```bash
sudo bootc switch ghcr.io/jtekk1/nelhua-mango:stable
sudo systemctl reboot
```

`:stable` is published on push-to-main; `:latest` is published nightly by the cron build. Use `:latest` if you want to follow HEAD, `:stable` for the deliberate channel.

## Verifying signatures

```bash
cosign verify --key cosign.pub ghcr.io/jtekk1/nelhua-mango:stable
```

The image bakes its policy into `/etc/containers/policy.json` and `/etc/containers/registries.d/nelhua-mango.yaml`, so once deployed the signing key is enforced for subsequent upgrades.

## Stage0 ↔ Stage1

This repo is intentionally separate from the [Nelhua](../meta/) planning workspace. The PRD describes the long-term BuildStream-based Jaguar distro; that's stage1. Work here informs what stage1 ships, but doesn't follow the PRD's platform/distro boundary or BuildStream architecture.
