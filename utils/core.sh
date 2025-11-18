#!/bin/bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

DOTFILE_DIR="$(
    cd "$SCRIPT_DIR/.." || exit && pwd
)"

DOTNAMES=(
    "my-profile"
    "bashrc"
    "inputrc"
    "tmux.conf"
    "gitconfig"
    "config/nvim"
    "config/kitty"
    "config/xdg-terminals.list"
)

echoinfo() {
    [[ -n "$VERBOSE" ]] &&
        if $VERBOSE; then
            echo -e "\e[32mINFO:\e[0m $1"
        fi
}

export DOTFILE_DIR DOTNAMES
export -f echoinfo
