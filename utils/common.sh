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
    "config/herdr/config.toml"
    "config/herdr-sessionizer/config.toml"
    "herdr-sessionizer"
    "herdr-sessionizer-preview"
)

EXTRAS=(
    "tmux.conf"
    "gitconfig"
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

# Commands share one mapping for installation and removal.
declare -A COMMAND_SOURCES=(
    ['herdr-sessionizer']="my-profile/scripts/herdr-sessionizer/picker.sh"
    ['herdr-sessionizer-preview']="my-profile/scripts/herdr-sessionizer/preview.sh"
)

resolve_target() {
    local target=$1 name
    for name in "${DOTNAMES[@]}"; do
        [[ $name == "$target" ]] || continue
        if [[ -n ${COMMAND_SOURCES[$target]:-} ]]; then
            LINK_SOURCE="$DOTFILE_DIR/${COMMAND_SOURCES[$target]}"
            LINK_DESTINATION="$HOME/.local/bin/$target"
        else
            LINK_SOURCE="$DOTFILE_DIR/$target"
            LINK_DESTINATION="$HOME/.$target"
        fi
        return 0
    done
    printf 'Unknown target: %s\n' "$target" >&2
    return 1
}

link_matches() {
    [[ -L $LINK_DESTINATION ]] &&
        [[ $(readlink -f -- "$LINK_DESTINATION") == "$(readlink -f -- "$LINK_SOURCE")" ]]
}
