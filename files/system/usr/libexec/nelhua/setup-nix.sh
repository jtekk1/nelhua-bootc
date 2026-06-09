#!/usr/bin/env bash
# Thin wrapper kept for back-compat with the existing nix-setup.service
# ExecStart path. The actual install logic lives in /usr/bin/nelhua-install-nix
# so the first-boot service, the future gum wizard, and manual user invocations
# all share one implementation.
set -euo pipefail
exec /usr/bin/nelhua-install-nix
