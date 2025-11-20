#!/usr/bin/env bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

. "$SCRIPT_DIR/common.sh"

SCRIPT_FILENAMES=(
    'core-dependencies-install.sh'
    'gh-install.sh'
    'ghostty-install.sh'
    'neovim-install.sh'
    'nvm-install.sh'
    'rust-install.sh'
    'uv-install.sh'
)

for SCRIPT_FILENAME in "${SCRIPT_FILENAMES[@]}"; do
    bash "$DEPENDENCIES_SCRIPTS_FOLDER/$SCRIPT_FILENAME"
done
