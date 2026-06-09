#!/usr/bin/env bash
# Launched from mango via exec-once on first login. If the wizard hasn't been
# completed, open it fullscreen in kitty. Otherwise do nothing.
set -u

MARKER="${HOME}/.config/nelhua/.setup-done"

if [[ -f "${MARKER}" ]]; then
    exit 0
fi

exec kitty \
    --start-as=fullscreen \
    --title="Nelhua Setup" \
    /usr/libexec/nelhua/first-boot-setup
