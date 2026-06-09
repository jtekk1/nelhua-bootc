# Build-context staging — kept off the final image via bind-mounts during RUN.
FROM scratch AS ctx
COPY build_files /
COPY cosign.pub /cosign.pub
COPY files/dnf /repos

FROM scratch AS sysfiles
COPY files/system /

# Base image — vanilla Fedora bootc, no upstream opinion to wrestle with.
FROM quay.io/fedora/fedora-bootc:44

ARG IMAGE_NAME=nelhua-mango
ARG IMAGE_REGISTRY_PATH=ghcr.io/jtekk1/nelhua-mango
ENV IMAGE_NAME=${IMAGE_NAME}
ENV IMAGE_REGISTRY_PATH=${IMAGE_REGISTRY_PATH}

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
