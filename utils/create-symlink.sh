#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function, DOTNAMES
source "$SCRIPT_DIR/core.sh"

if [[ -z $1 ]]; then
    echoinfo "No input provided, skipping"
    exit 1
fi

DOTNAME="$1"
COLORDOTNAME="\e[36m$DOTNAME\e[0m"

if [[ ! ${DOTNAMES[*]} =~ $DOTNAME ]]; then
    echoinfo "$COLORDOTNAME not in available dotfiles\e[36m"
    echo "["
    for NAME in "${DOTNAMES[@]}"; do
        echo "  $NAME"
    done
    echo "]"
    echoinfo "Input dotfile name should not start with ."
    exit 1
fi

echoinfo "Creating symlink for $COLORDOTNAME"

SYMLINK_TARGET="$HOME/.$DOTNAME"

if [[ ! -L $SYMLINK_TARGET ]]; then
    echoinfo "$COLORDOTNAME symlink not found, creating"
    ln -s "$DOTFILE_DIR/$DOTNAME" "$SYMLINK_TARGET"
    echoinfo "Finished creating $COLORDOTNAME symlink"
else
    echoinfo "$COLORDOTNAME symlink already exists, skipping"
fi
