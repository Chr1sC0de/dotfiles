#!/usr/bin/env bash

# import the DOTFILE_DIR variable, echoinfo function, DOTNAMES
. "utils/common.sh"

for DOTNAME in "${DOTNAMES[@]}"; do
    "utils/symlink-remove.sh" "$DOTNAME"
done
