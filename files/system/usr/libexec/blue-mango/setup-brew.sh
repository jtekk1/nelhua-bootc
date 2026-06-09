#!/usr/bin/env bash
# Thin wrapper kept for back-compat with the existing brew-setup.service
# ExecStart path. The actual install logic lives in /usr/bin/nelhua-install-brew
# so the first-boot service, the future gum wizard, and manual user invocations
# all share one implementation.
set -euo pipefail
exec /usr/bin/nelhua-install-brew
