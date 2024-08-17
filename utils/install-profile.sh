#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function
source "$SCRIPT_DIR/core.sh"

echoinfo "Creating symlink for the Profile"

if [[ ! -L $HOME/Profile ]]; then
    echoinfo "Profile not found creating symlink"
    ln -s "$DOTFILE_DIR/Profile" "$HOME/Profile"
    echoinfo "Finished creating Profile symlink"
else
    echoinfo "Profile symlink already exists"
fi
