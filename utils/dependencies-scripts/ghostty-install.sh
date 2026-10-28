#!/usr/bin/env bash
set -euo pipefail

# Provision sudo for the upstream installer even when bootstrapping as root.
bash "$(dirname "${BASH_SOURCE[0]}")/../apt-install-missing.sh" sudo libgtk-4-dev
installer=$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)
bash -c "$installer"
