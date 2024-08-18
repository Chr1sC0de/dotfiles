#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function, DOTNAMES
source "$SCRIPT_DIR/core.sh"

for DOTNAME in "${DOTNAMES[@]}"; do
    # echoinfo "\e[36mCreating symlink for $DOTNAME"
    #
    # SYMLINK_TARGET="$HOME/.$DOTNAME"
    #
    # if [[ ! -L $SYMLINK_TARGET ]]; then
    #     echoinfo "\e[31m$DOTNAME symlink not found, creating"
    #     ln -s "$DOTFILE_DIR/$DOTNAME" "$SYMLINK_TARGET"
    #     echoinfo "\e[31mFinished creating $DOTNAME symlink"
    # else
    #     echoinfo "\e[31m$DOTNAME symlink already exists"
    # fi
    "$SCRIPT_DIR"/"create-symlink.sh" "$DOTNAME"

done
