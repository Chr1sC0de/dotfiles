#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

UTILS_DIR="$SCRIPT_DIR/utils"

bash "$UTILS_DIR/dependencies-install-all.sh"
bash "$UTILS_DIR/dotfiles-install.sh" -f --tmux
bash "$UTILS_DIR/profile-to-bashrc.sh"

. "$HOME/.bashrc"
