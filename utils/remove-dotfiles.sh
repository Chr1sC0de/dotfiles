#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function
source "$SCRIPT_DIR/core.sh"

for DOTNAME in "${DOTNAMES[@]}"; do
    echoinfo "Removing symlink for $DOTNAME"

    SYMLINK_TARGET="$HOME/.$DOTNAME"

    if [[ -L $SYMLINK_TARGET ]]; then
        echoinfo "$DOTNAME symlink found removing"
        rm "$SYMLINK_TARGET"
        echoinfo "Finished removing $DOTNAME symlink"
    else
        echoinfo "$DOTNAME not found"
    fi
done
