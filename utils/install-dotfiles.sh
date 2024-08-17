#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function, DOTNAMES
source "$SCRIPT_DIR/core.sh"

for DOTNAME in "${DOTNAMES[@]}"; do
    echoinfo "Creating symlink for $DOTNAME"

    SYMLINK_TARGET="$HOME/.$DOTNAME"

    if [[ ! -L $SYMLINK_TARGET ]]; then
        echoinfo "$DOTNAME symlink not found creating"
        ln -s "$DOTFILE_DIR/$DOTNAME" "$SYMLINK_TARGET"
        echoinfo "Finished creating $DOTNAME symlink"
    else
        echoinfo "$DOTNAME symlink already exists"
    fi
done
