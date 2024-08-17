#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

DOTFILE_DIR="$(
    cd "$SCRIPT_DIR/.." || exit && pwd
)"

DOTNAMES=(
    ".my-profile"
    ".bashrc"
)

echoinfo() {
    echo "INFO: $1"
}

export DOTFILE_DIR DOTNAMES
export -f echoinfo
