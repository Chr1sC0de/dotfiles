#!/usr/bin/env bash

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

DOTFILE_DIR="$(
    cd "$SCRIPT_DIR/.." || exit && pwd
)"

DEPENDENCIES_SCRIPTS_FOLDER="utils/dependencies-scripts"

DEFAULTS=(
    "my-profile"
    "config/nvim"
    "config/codebook"
    "inputrc"
)

EXTRAS=(
    "tmux.conf"
    "gitconfig"
    "config/herdr/config.toml"
    "config/kitty"
    "config/xdg-terminals.list"
)

DOTNAMES=("${DEFAULTS[@]}" "${EXTRAS[@]}")

echoinfo() {
    [[ -n "$VERBOSE" ]] &&
        if $VERBOSE; then
            echo -e "\e[32mINFO:\e[0m $1"
        fi
}

export DOTFILE_DIR DEFAULTS EXTRAS DOTNAMES DEPENDENCIES_SCRIPTS_FOLDER
export -f echoinfo
