#!/usr/bin/env bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function, DOTNAMES
source "$SCRIPT_DIR/common.sh"

for DOTNAME in "${DOTNAMES[@]}"; do
    "$SCRIPT_DIR"/"symlink-remove.sh" "$DOTNAME"
done
