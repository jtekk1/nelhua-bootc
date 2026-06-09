#!/usr/bin/env bash
set -euo pipefail

[[ -x /home/linuxbrew/.linuxbrew/bin/brew ]] && exit 0

getent passwd linuxbrew >/dev/null || \
  useradd -r -m -d /var/home/linuxbrew -s /bin/bash linuxbrew

runuser -u linuxbrew -- env NONINTERACTIVE=1 /bin/bash -c \
  '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
