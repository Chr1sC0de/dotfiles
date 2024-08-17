#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

DOTFILE_DIR="$(
    cd "$SCRIPT_DIR/.." || exit && pwd
)"

echoinfo() {
    echo "INFO: $1"
}

export DOTFILE_DIR
export -f echoinfo
