#!/usr/bin/env bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

UTILS_DIR="$SCRIPT_DIR/utils"

bash "$UTILS_DIR/dependencies-install-all.sh"
bash "$UTILS_DIR/dotfiles-install.sh" --tmux --gitconfig
bash "$UTILS_DIR/profile-to-bashrc.sh"

. "$HOME/.bashrc"
