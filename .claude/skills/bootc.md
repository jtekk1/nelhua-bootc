---
name: bootc
description: Domain knowledge for working with bootc — image-based OS updates via OCI registries. Covers the bootc CLI, Containerfile patterns for bootc base images, bootc-image-builder (BIB) for disk/ISO output, signing policy, and anti-patterns specific to the nelhua-linux-bootc project. Read this BEFORE touching the Containerfile, build_files/build.sh, disk_config/*.toml, .github/workflows/build*.yml, or any cosign/policy.json work.
---

# bootc skill — nelhua-linux-bootc reference

This is a living reference. When you (a future agent) learn something new about bootc that wasn't here — **add it**. Don't let this rot.

## What bootc is

`bootc` is a CLI that manages transactional, in-place OS updates by treating bootable host systems as OCI/Docker container images. The container image bundles the Linux kernel plus userspace. Updates pull a new manifest from an OCI registry, stage the change, and activate it on next reboot. ostree + composefs are the storage backend; you generally don't touch them directly.

Project: https://github.com/bootc-dev/bootc — book at https://bootc.dev/bootc/

Key implication: **the OS is a single OCI image**. There is no separate "base system update" vs. "package update." If you want a package on the system, it goes in the Containerfile. If you want it removable per-user, it's a Flatpak or Distrobox or Homebrew.

## bootc CLI surface

| Command | What it does |
|---|---|
| `bootc status` | Show currently booted image, staged image, rollback target |
| `bootc switch <image>` | Replace the booted image reference (e.g. switch from upstream to a fork) |
| `bootc upgrade` | Pull and stage the latest matching tag |
| `bootc rollback` | Boot the previous deployment on next reboot |
| `bootc install to-filesystem <path>` | Install a bootc image onto an existing partition layout (used by anaconda kickstart) |
| `bootc install to-disk <disk>` | Install onto a raw disk |
| `bootc edit` | Edit the bootc spec (image reference, etc.) |

`bootc switch --mutate-in-place --transport registry <image>` is the kickstart-friendly form — see `disk_config/iso.toml`'s `%post` section in this repo.

### `bootc upgrade` vs `rpm-ostree upgrade` when layered packages exist

`bootc upgrade` is strict — it **refuses to run** when the booted deployment has any `rpm-ostree install`-layered packages, returning:

```
error: Upgrading: Deployment contains local rpm-ostree modifications; cannot upgrade via bootc. You can run `rpm-ostree reset` to undo the modifications.
```

This is by design: the OCI image layer model and the rpm-ostree package layer model can't be safely composed. Two recovery paths:

1. **Drop the overrides** — `sudo rpm-ostree reset` removes all layered packages and overrides, returning the deployment to pure bootc state. Then `sudo bootc upgrade` works. Use this when the layered packages are about to be baked into the new image anyway (typical dev workflow: layer for the day, reset when the bake catches up).
2. **Use `rpm-ostree upgrade`** — works in *both* cases. Dispatches to bootc when there are no modifications, stays in rpm-ostree-land when there are. Less canonical but always works.

The `nelhua-update` wrapper (planned, task 3 in plan.md) tries `bootc upgrade` first and falls back to `rpm-ostree upgrade` on this specific error. That's the pragmatic answer for users who layer packages during dev.

## Containerfile patterns for bootc

Base images you'll see in this ecosystem:
- `quay.io/fedora/fedora-bootc:NN` — vanilla Fedora bootc (this repo uses `:44`)
- `quay.io/centos-bootc/centos-bootc:streamNN` — CentOS Stream
- `ghcr.io/ublue-os/bluefin:stable` / `aurora:stable` / `bazzite:stable` — Universal Blue's opinionated derivatives (GNOME / KDE / gaming respectively)
- `ghcr.io/ublue-os/base-main:latest` — minimal UB base

**Build context pattern used in this repo:**

```dockerfile
FROM scratch AS ctx
COPY build_files /
COPY cosign.pub /cosign.pub
COPY files/dnf /repos

FROM scratch AS sysfiles
COPY files/system /

FROM quay.io/fedora/fedora-bootc:44

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=sysfiles,source=/,target=/system-files \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN bootc container lint
```

Why bind-mounts: `/ctx` (build script + signing pubkey + repo files) and `/system-files` (the runtime overlay tree) are kept out of the final image's layers. The single `RUN` invokes `build.sh` which does everything; the closing `bootc container lint` validates conformance.

**Always end with `RUN bootc container lint`.** It catches mistakes like writing to `/var` at build time (those writes won't survive deployment) or leaving package manager state in places ostree doesn't expect.

## build.sh structure (this repo)

`build_files/build.sh` is structured as ordered named functions called from `main()`:

1. `enable_repos` — RPMFusion, COPRs, third-party `.repo` files (terra, tailscale, tekk)
2. `install_base` — base CLI/TUI/GUI/fonts utilities + desktop packages
3. `install_hardware` — Mesa, AMD/Intel firmware, vulkan loaders
4. `setup_plymouth` — boot splash theme
5. **`install_desktop`** — dispatches to `install_desktop_mango` (mango WM + session deps + greetd + iwd) or `install_desktop_kde` (kinoite ships Plasma; this is the opinion layer) based on `$DESKTOP` env (set from the `DESKTOP` build-arg)
6. `install_extras` — gaming + dev + virt tools
7. `install_blesh` / `install_superfile` — vendored binaries from upstream releases
8. `apply_files` — `rsync -rlptD /system-files/ /` brings the overlay tree into the image
9. `enable_brew_setup` — enables the first-boot Homebrew bootstrap service (unit shipped via `files/system/`)
10. `remove_unwanted` — strips out packages we don't want (e.g. firefox; the picker UX installs the user's chosen browser as a Flatpak)
11. `apply_signing` — installs the cosign pubkey, registers it in `containers-policy.json`
12. `apply_os_release` — sets `PRETTY_NAME` (variant-aware: "Mango Edition" vs "KDE")
13. `cleanup_var_state` / `generate_var_tmpfiles` / `cleanup` — final scrub + tmpfiles.d

**Order matters.** `apply_files` MUST run before `enable_brew_setup` because the service unit lives in `files/system/etc/systemd/system/brew-setup.service`. `enable_repos` MUST run before any `install_*`. `apply_signing` should run after `apply_files` so it doesn't get overwritten.

**Variant model.** The `$DESKTOP` env (set from `--build-arg DESKTOP=...`) drives the dispatch in `install_desktop` and the `PRETTY_NAME` switch in `apply_os_release`. Kinoite ships Plasma + SDDM + xdg-desktop-portal-kde + NetworkManager, so `install_desktop_kde` is currently a no-op — the opinion layer (KDE Connect, breeze-dark default, panel layout) lives in `plan.md` task K4 as it's decided. `install_desktop_mango` installs the Wayland WM stack + greetd + iwd because fedora-bootc base has none of that.

## bootc-image-builder (BIB)

BIB turns a bootc OCI image into an installable disk image (qcow2 / anaconda-iso / raw / vmdk / etc.). Documentation: https://osbuild.org/docs/bootc/

**Invocation pattern (this repo's `build-qcow2.sh` / `build-iso.sh`):**

```bash
sudo podman run --rm -it --privileged --pull=newer --net=host \
  --security-opt label=type:unconfined_t \
  -v "$(realpath disk_config/disk.toml):/config.toml:ro" \
  -v "$(pwd)/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --use-librepo=True --rootfs=btrfs \
  nelhua-mango:latest
```

Output lands in `output/<type>/`. The container storage bind-mount lets BIB resolve `nelhua-mango:latest` from rootful podman without re-pulling.

**Config TOML knobs used in this repo:**

| Section | Used for |
|---|---|
| `[[customizations.filesystem]]` | Partition mountpoints + minsize (e.g. `/ = 20 GiB`) |
| `[customizations.installer.kickstart]` | `%post` block with `bootc switch --mutate-in-place ...` to point the installed system at our registry |
| `[customizations.installer.modules]` | Enable/disable anaconda modules (Storage, Runtime, Subscription, etc.) |
| `[customizations.kernel] append = "..."` | Kernel args at install boot — solves what `bluebuild generate-iso` couldn't pass through. Use for `plymouth.enable=0`, `console=tty1`, `inst.nokill`, etc. |

Other knobs not used here but worth knowing: `[customizations.user]` (preset users), `[customizations.iso]` (volume IDs).

## Image signing (cosign + policy.json)

This repo bakes its signing policy into the image so a deployed system verifies `bootc upgrade` against the same key it was signed with.

**Build-time pieces (handled by `apply_signing` in `build.sh`):**

- Copy `cosign.pub` to `/etc/pki/containers/<image-name>.pub`
- Create `/etc/containers/registries.d/<image-name>.yaml` with `use-sigstore-attachments: true`
- Patch `/etc/containers/policy.json` to require `sigstoreSigned` for our registry path

**CI signing (handled in `.github/workflows/build.yml`):**

- Workflow checks out, builds with buildah, pushes with `redhat-actions/push-to-registry`, then signs each pushed tag with `cosign sign -y --key env://COSIGN_PRIVATE_KEY`
- `COSIGN_PRIVATE_KEY` comes from the `SIGNING_SECRET` repo secret
- The signing pubkey is `cosign.pub`, committed to the repo
- **`cosign.key` must never be committed.** `.gitignore` has it; if you ever see it tracked, rotate immediately

**Verification a user can run:**

```bash
cosign verify --key cosign.pub ghcr.io/jtekk1/nelhua-mango:stable
```

## CI workflows (this repo)

`build.yml` is a **2D matrix** of `desktop × channel`:

| Axis | Values |
|---|---|
| `matrix.desktop` | `mango` (base `quay.io/fedora/fedora-bootc:N`, image `nelhua-mango`) — `kde` (base `quay.io/fedora/fedora-kinoite:N`, image `nelhua-kde`) |
| `matrix.channel` | `stable` (base tag `44`) — `rawhide` (base tag `rawhide`) |

= 4 cells per trigger: `mango/stable`, `mango/rawhide`, `kde/stable`, `kde/rawhide`. Each cell pushes to its own ghcr.io image (`nelhua-mango` or `nelhua-kde`), signed independently.

Channel name in each cell maps to OCI tag set as follows.

`stable` channel:

| Trigger | Tag(s) |
|---|---|
| `push` to `main` branch | `:latest` (+ dated `:latest.YYYYMMDD`) |
| `push` of `v*` git tag | `:stable` (+ dated) AND `:v<tag>` (immutable pin) |
| `workflow_dispatch` | `:stable` (+ dated) |
| `schedule` (cron, 10:05 UTC daily) | `:latest` — catch-up; main pushes already cover it |
| `pull_request` | `:pr-<N>` (+ dated) and `:sha-<short>` — built but **not pushed** |

`rawhide` channel:

| Trigger | Tag(s) |
|---|---|
| All non-PR triggers | `:rawhide` (+ dated `:rawhide.YYYYMMDD`) |
| `pull_request` | `:rawhide-pr-<N>` (+ dated) — built but **not pushed** |

Rawhide cells are marked `continue-on-error: true` because Terra / Tekk / COPR repos and Kinoite-rawhide may not exist or have F45 parity yet; rawhide failures don't fail the workflow as long as the stable cells succeed. Additionally, `build_files/build.sh` detects rawhide (via `PRETTY_NAME` containing "Rawhide") and downgrades to soft-fail mode for that build: third-party repo enables (Terra, Tekk) become skip-with-warning if their URL 404s, and all `dnf5 install` calls in the package-install groups use `--skip-unavailable` so missing packages don't abort the transaction. The result is a "lite" rawhide image (missing whatever Terra/Tekk/COPR haven't published yet) instead of no rawhide image. Stable stays strict — any missing package or repo on a stable build is a hard fail. Build args wired per cell: `BASE_IMAGE=<base_repo>:<base_tag>`, `IMAGE_NAME`, `IMAGE_REGISTRY_PATH`, `DESKTOP=mango|kde`. The Containerfile declares `ARG BASE_IMAGE` globally before any `FROM`; the other three are stage-local in the final stage.

Important semantic: `:latest` tracks tip-of-main; `:stable` is deliberate (manual dispatch or a `v*` tag). `:latest` is never behind `:stable`; the two are equal momentarily right after a `:stable` cut, then `:latest` advances with subsequent merges. This matches the conventional UB/Bazzite/Bluefin meaning (`:latest` = moving newest, `:stable` = curated). An earlier iteration of this workflow had the mapping inverted; if you spot stale references in docs to "stable updates on push to main", that's a pre-2026-06-09 fingerprint and should be updated.

`build-disk.yml` is manual (`workflow_dispatch`) and builds qcow2 + anaconda-iso via `osbuild/bootc-image-builder-action`. Inputs let you pick `amd64`/`arm64` runner, target tag, and S3 upload. Also triggers on PRs that touch `disk_config/*.toml` or this workflow file.

## Dogfooding: running VMs from this OS

If users will run `./run-vm.sh` (or any qemu/systemd-vmspawn workflow) from a daily-driver bootc image, the host needs the **virt trio**:

- `edk2-ovmf` — UEFI firmware blob for guests
- `systemd-container` — provides `systemd-vmspawn` (split from base systemd on F44+)
- `qemu-system-x86-core` — minimal x86 emulator

…**plus SPICE subpackages** if you want a GUI console (`systemd-vmspawn --console=gui` requires `spicevmc` char device):

- `qemu-char-spice` (the char backend; missing this gives `'spicevmc' is not a valid char driver name`)
- `qemu-ui-spice-app` (SPICE GUI integration)
- `qemu-ui-gtk` (GTK display backend; without it qemu falls back to VNC silently — symptom is `VNC server running on ::1:5900` when you expected a window)
- `qemu-audio-spice`
- `qemu-device-display-virtio-gpu` (virtio GPU in the guest)

Fedora splits qemu into ~30 narrow subpackages — `qemu-system-x86-core` is genuinely minimal. The metapackage `qemu-kvm` pulls a sensible default set but is heavier; the explicit list above is what `install_extras` in `build_files/build.sh` ships.

## Rootless vs rootful podman (local builds)

`./build.sh` runs `podman build` as the regular user — image lands in **rootless** storage (`~/.local/share/containers/storage`). `./build-qcow2.sh` and `./build-iso.sh` run `sudo podman` because bootc-image-builder requires privileged mode — they read from **rootful** storage (`/var/lib/containers/storage`). Different stores; BIB fails with `image not known` if the rootless-built image was never copied over.

Both BIB scripts include an `ensure_rootful_image` helper that compares image IDs in rootless vs rootful and runs `podman image scp ${UID}@localhost::IMAGE root@localhost::IMAGE` when needed. Don't remove it without replacing the same logic somewhere — and don't expect BIB to auto-pull anymore (newer BIB versions emit "bootc-image-builder no longer pulls images" if asked to fetch).

This problem does not exist in CI — the GH Actions workflow uses `redhat-actions/buildah-build` and `osbuild/bootc-image-builder-action`, both of which see the same root storage.

**Always pass a fully-qualified image reference to BIB** — e.g. `localhost/nelhua-mango:latest`, not bare `nelhua-mango:latest`. BIB normalizes bare names to `docker.io/library/...` and then can't resolve them locally. The CI workflow uses `ghcr.io/...` paths so this only bites local builds.

## Network reachability from CI

The repos enabled in `build_files/build.sh` are fetched at build time. From GitHub-hosted runners, **`forgejo.jtekk.dev` returns HTTP 403** (bot protection blocks the GH runner IP range). The user's daily driver and tailnet get 200 — the URL itself is correct.

Practical implications:
- Any new `curl`/`dnf` URL pointing at `forgejo.jtekk.dev/api/packages/...` will break GH-runner builds unless it carries an auth token **or** a package-manager-shaped User-Agent.
- **What works today (cheapest fix):** spoof a libdnf UA on curl. This is what `enable_repos` in `build_files/build.sh` does for the Tekk repo file. The bot wall gates on `curl/*` UA from datacenter IPs but allow-lists package managers:
  ```bash
  curl -fsSL -A "libdnf (Fedora ${OS_VERSION}; x86_64)" \
    -o /etc/yum.repos.d/tekk-fedora.repo \
    "https://forgejo.jtekk.dev/api/packages/TekkRPM/rpm/tekk-fedora-${OS_VERSION}.repo"
  ```
  Once the `.repo` file is in place, subsequent `dnf install` calls naturally use libdnf's UA and pass through. If the wall hardens (e.g. moves from UA-gating to IP-gating), this stops working and we fall back to options below.
- **More durable fixes:** (1) `Authorization: token $FORGEJO_TOKEN` from a GH secret — explicit auth; (2) mirror packages to Copr / OBS / a public OCI yum repo — eliminates the wall entirely and helps third-party users; (3) run the build on the Forgejo Actions runner (`frank-da-tank`) — matches the long-term plan.
- If a third-party user ever runs this image and does `bootc upgrade` or any subsequent `dnf` operation against tekk packages, **they too will need access** — the bot protection isn't a CI-only concern. UA spoofing in dnf works for them too if their distro's dnf uses a recognizable UA, but the real answer is option (2) above.

## dnf5 quirks on fedora-bootc

The fedora-bootc base image ships `dnf5` (not `dnf` / `dnf4`). Things to know:

- **`copr` is a separate plugin in dnf5.** `dnf5 copr enable foo/bar` will fail with `Unknown argument "copr"` unless you first `dnf5 -y install 'dnf5-command(copr)'`. dnf4 had copr built in; this is a regression in practice. See `enable_repos` in `build_files/build.sh` for the install-first pattern.
- **Use `dnf5 -y install <PACKAGE-MANAGER-EXPRESSION>` for plugins**, not `dnf5 plugin install`. The plugin packages are named `dnf5-command(<name>)` (a Requires expression that resolves to the actual rpm).
- **`--skip-unavailable` is a per-subcommand flag, not a global.** It belongs *after* `install`, not before:
  - ✅ `dnf5 -y install --skip-unavailable foo bar`
  - ❌ `dnf5 -y --skip-unavailable install foo bar` (errors with "Unknown argument", confusingly does list the right subcommands)
  - The `dnf_install()` helper in `build_files/build.sh` enforces the right ordering — use it instead of inlining the flag.
- Other dnf5-vs-dnf4 differences worth checking before reaching for: `dnf5 install`, `dnf5 remove`, `dnf5 clean all` all behave like their dnf4 counterparts.

## `bootc container lint` warnings we see and how to address them

`bootc container lint` is the final step in `Containerfile`. As of this build, the image passes 11 checks with 2 warnings. The warnings don't block the build but should be cleaned up because they signal real correctness issues at first boot.

### `nonempty-run-tmp`

**What it says:** content remains in `/run` (and sometimes `/tmp`) at image-finalization time — e.g. `/run/dnf`, `/run/lock`, `/run/selinux-policy`.

**Why it matters:** `/run` and `/tmp` are runtime-only tmpfs. Files baked into the image layer here are dead weight — they get masked at boot but bloat the image and confuse layer hashing.

**Fix:** at the end of `cleanup()` in `build_files/build.sh`, add `rm -rf /run/* /tmp/*` (the `/tmp` mount is already a build-time tmpfs via Containerfile, but the runtime layer can still have leftover content from packages that wrote there during install). The Containerfile already does `--mount=type=tmpfs,dst=/tmp` for the RUN step but anything written before that mount existed (in earlier stages) can persist.

### `var-tmpfiles`

**What it says:** content exists in `/var` that won't survive first boot. bootc resets `/var` from `/usr/share/factory/var/` on first boot via systemd-tmpfiles. Two sub-warnings:
1. **Directories like `/var/lib/AccountsService`, `/var/lib/blueman`, `/var/lib/greetd`** are created by package post-install scriptlets, but the package itself doesn't ship a tmpfiles.d entry telling systemd to recreate them. On first boot they vanish; services that expect them may misbehave.
2. **State files like `/var/lib/dnf/...`, `/var/lib/plocate/CACHEDIR.TAG`, `/var/lib/authselect/checksum`** are pure runtime state that shouldn't be in the image at all.

**Two-part fix:**
1. **Delete state files** in `cleanup()`:
   ```bash
   rm -rf /var/lib/dnf /var/lib/plocate /var/cache/* /var/log/*
   rm -f  /var/lib/authselect/checksum
   ```
2. **Ship tmpfiles.d entries** for the directories that need to be recreated. Either ship a static config (e.g. `files/system/usr/lib/tmpfiles.d/nelhua-bootc.conf` listing each `d /var/lib/foo 0755 root root - -`), or generate it dynamically near the end of build.sh by walking what's in /var/lib at that point. Universal Blue's images include a script that does this; pattern reference: `bluefin`'s `var-to-tmpfiles.sh`.

### `Found non-directory/non-symlink files in /var`

Same root cause as `var-tmpfiles`. Listed files (the dnf locks, countme counters, plocate cache tags) are pure state and should be deleted in `cleanup()`.

## `/opt` symlink gotcha (Kinoite + recent fedora-bootc)

Some Fedora bootc/atomic bases ship `/opt` as a **symlink to `/var/opt`** so it remains user-writable on the deployed system. rpm scriptlets that install into `/opt/<vendor>/` (`helium-browser`, `google-chrome`, `docker-desktop`, ...) fail at build time with `[RPM] mkdir failed - File exists` followed by `mkdir failed - No such file or directory`.

Fix: replace the symlink with a real directory before any package install runs. Containerfile has an idempotent step right after the final `FROM`:

```dockerfile
RUN if [ -L /opt ]; then rm /opt && mkdir -p /opt; fi
```

Side effect: `/opt` is no longer writable at runtime (becomes part of the read-only /usr ostree commit). For Nelhua's use case (we don't expect users to manually drop binaries in /opt — they use Flatpak/Brew/Nix) that's the right trade. If a future package needs /opt to be writable post-deploy, options are (a) make that package install elsewhere via a build-time symlink swap, or (b) revert the /opt fix and find a different way to make the affected rpm install (rare).

## Nix conventions (this repo)

Nix is opt-in: `/nix` is pre-created in the image but the installer doesn't run until the user invokes it. The first-boot `nix-setup.service` is a no-op unless the user has actually run `nelhua-install-nix` (or the wizard surfaces it). Locked-in decisions:

- **Determinate over upstream** — `nelhua-install-nix` uses the [Determinate](https://determinate.systems/) installer. Handles SELinux, ostree-aware, manages `nix-daemon` as a proper systemd unit. Determinate v3 dropped the positional `linux` planner — the planner is auto-detected. Don't re-add it.
- **Flakes-only** — `experimental-features = nix-command flakes` enabled system-wide via the drop-in at `files/system/etc/nix/nix.conf.d/10-nelhua.conf`. **Note `extra-experimental-features`**, not `experimental-features` — Determinate sets some features already and we want to *append*, not replace. We do **not** seed any nix-channels.
- **Trusted users** — `root @wheel`. Wheel members can pin substituters and use binary caches without re-confirming. Members of `wheel` already have sudo, so the additional trust is consistent with what they already have.
- **No home-manager bundled by default** — keeps the base image lean. If users want it, the canonical path is `nix profile install nixpkgs#home-manager` from a flake. A future `nelhua-install-home-manager` script is reasonable if demand justifies it (track in `plan.md`).
- **GC schedule** — `nix-gc.timer` runs weekly (`Sun *-*-* 03:30:00`, persistent, randomized ±30min) → `nix-gc.service` runs `nix-collect-garbage -d --delete-older-than 30d`. The unit is `ConditionPathExists`-guarded on the Determinate-installed `nix-collect-garbage` binary, so it's a no-op until Nix is actually installed. **Don't change retention to less than 30 days** without considering that users may build dev shells they reuse over weeks.

When updating this section, also touch `plan.md`'s parked "Nix sub-questions" entry — both should agree.

## Anti-patterns (do not do these)

- **Writing to `/var` at build time** — bootc resets `/var` from `/usr/share/factory/var/` on first boot. Build-time writes are lost. Put state in `/usr` or in a systemd unit that creates it at first boot.
- **`dracut -f --regenerate-all` in the Containerfile** — was carried over from BlueBuild; doesn't make sense in bootc because initramfs is rebuilt by BIB (or the deployed system), not the container. plan.md flagged this as a suspected cause of plymouth issues. Don't reintroduce it.
- **Pinning `:latest` from base images** in production Containerfiles without a renovate / dependabot bump path — the FROM line should be either explicitly versioned (`:44`) or auto-bumped.
- **Modifying `/etc/containers/policy.json` without preserving existing transports** — `apply_signing` uses Python to merge, not overwrite. If you replace it, you'll break verification for upstream images.
- **Adding NVIDIA support to base mango image** — out of scope. Stage1 (Jaguar) inherits this from `meta/docs/PRD.md` §16.
- **Layering packages from the user-facing side** — there is no `dnf install` exposed to the user. New packages go in `build_files/build.sh` and ship with the next image.
- **Skipping `RUN bootc container lint`** — it's the cheapest correctness check we have.

## Stage0 / Stage1 context

This repo (`nelhua-linux-bootc`) is **stage0** of a two-stage trajectory. The eventual stage1 distro (Jaguar) lives in `meta/` as a planning workspace and will be built with BuildStream, not Containerfile derivation. Don't drag PRD/AGENTS.md constraints from `meta/` into stage0 work — they describe the stage1 endpoint, not the stage0 path. Do preserve continuity in naming and packaging choices so lessons feed forward.

## Commit handoff

When work is ready to commit, the workflow is:

1. **Stage explicitly** — `git add <specific paths>`, never `git add -A` or `git add .`. `.gitignore` covers the obvious traps (`cosign.key`, `output/`, `commit*.txt`) but bare `-A` is still risky for editor swap files, transient ISOs, etc.
2. **Write the message to `commit.txt`** at repo root. `.gitignore` already covers `commit.txt` and `commit-*.txt` (the "Commit message scratch files" entry). Use Conventional Commits v1.0.0 — `type(scope): description` subject, body wrapped near 72 chars, footers last.
3. **Stop there.** The user runs `git commit -F commit.txt` themselves. Do NOT run `git commit`. Do NOT add `Co-Authored-By: Claude ...` or "Generated by Claude Code" trailers — neither in the file nor anywhere else. (Hard rule, project-wide.)
4. **Summarize the handoff** in your final message: which paths are staged, that the message is in `commit.txt`, ready for `git commit -F commit.txt`. If you're proposing a multi-commit split, write `commit-1.txt`, `commit-2.txt`, etc., and call out the staging order.

Why a file instead of pasting in chat: `git commit -F` preserves exact whitespace, bullet lists, code fences, and ~72-char wrapping. Chat copy-paste corrupts those in subtle ways and the user has to clean them up.

## References

- bootc: https://github.com/bootc-dev/bootc | book: https://bootc.dev/bootc/
- bootc-image-builder: https://github.com/osbuild/bootc-image-builder | docs: https://osbuild.org/docs/bootc/
- Universal Blue image-template (the migration target shape): https://github.com/ublue-os/image-template
- Fedora bootc base images: https://quay.io/repository/fedora/fedora-bootc
- cosign: https://github.com/sigstore/cosign
- Container signing policy format: `man 5 containers-policy.json`
