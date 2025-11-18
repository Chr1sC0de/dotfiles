#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function, DOTNAMES
source "$SCRIPT_DIR/core.sh"

for DOTNAME in "${DOTNAMES[@]}"; do
    "$SCRIPT_DIR"/"create-symlink.sh" "$DOTNAME" -v -f
done
