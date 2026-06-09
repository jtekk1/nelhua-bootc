# Global ARG declared before any FROM — allows overriding the base via
# --build-arg BASE_IMAGE=... (CI matrix builds stable vs rawhide this way).
ARG BASE_IMAGE=quay.io/fedora/fedora-bootc:44

# Build-context staging — kept off the final image via bind-mounts during RUN.
FROM scratch AS ctx
COPY build_files /
COPY cosign.pub /cosign.pub
COPY files/dnf /repos

FROM scratch AS sysfiles
COPY files/system /

# Base image — vanilla Fedora bootc by default; override with BASE_IMAGE
# build-arg (e.g. quay.io/fedora/fedora-bootc:rawhide).
FROM ${BASE_IMAGE}

ARG IMAGE_NAME=nelhua-mango
ARG IMAGE_REGISTRY_PATH=ghcr.io/jtekk1/nelhua-mango
ARG DESKTOP=mango
ENV IMAGE_NAME=${IMAGE_NAME}
ENV IMAGE_REGISTRY_PATH=${IMAGE_REGISTRY_PATH}
ENV DESKTOP=${DESKTOP}

# Kinoite (and recent fedora-bootc) ships /opt as a symlink to /var/opt so it
# stays user-writable post-deploy. rpm scriptlets that install into /opt
# (helium-browser, google-chrome, docker-desktop, ...) fail at build time
# against that symlink with "mkdir failed: File exists / No such file or
# directory". Replace with a real directory before any package install runs.
# Idempotent — no-op if /opt is already a regular dir.
RUN if [ -L /opt ]; then rm /opt && mkdir -p /opt; fi

# Single RUN performs all customization. Bind-mounts give the script access to
# /ctx (build_files + cosign.pub + repo files) and /system-files (files/system
# tree, merged into rootfs at the end of the script).
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=sysfiles,source=/,target=/system-files \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN bootc container lint
