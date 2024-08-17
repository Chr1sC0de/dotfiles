#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function, DOTNAMES
source "$SCRIPT_DIR/core.sh"

for DOTNAME in "${DOTNAMES[@]}"; do
    echoinfo "\e[36mRemoving symlink for $DOTNAME"

    SYMLINK_TARGET="$HOME/.$DOTNAME"

    if [[ -L $SYMLINK_TARGET ]]; then
        echoinfo "\e[31m$DOTNAME symlink found, removing"
        rm "$SYMLINK_TARGET"
        echoinfo "\e[31mFinished removing $DOTNAME symlink"
    else
        echoinfo "\e[31m$DOTNAME not found"
    fi
done
