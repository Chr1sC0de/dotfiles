#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function
source "$SCRIPT_DIR/core.sh"

echoinfo "Removing Profile Symlink"

PROFILE_DIR="$HOME/Profile"

if [[ -L $PROFILE_DIR ]]; then
    echoinfo "Profile symlink found, removing"
    rm "$HOME/Profile"
    echoinfo "Finished symlink removing Profile"
else
    echoinfo "Profile symlink not found"
fi
