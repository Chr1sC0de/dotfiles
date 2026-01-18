#!/usr/bin/env -S bash -x

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

. "$SCRIPT_DIR/common.sh"

CORE_SCRIPTS=(
    "core-dependencies-install.sh"
    "rust-install.sh"
    "nvm-install.sh"
    "uv-install.sh"
    "grip-grab-install.sh"
    "eza-install.sh"
    "neovim-install.sh"
    "direnv-install.sh"
    "lazygit.sh"
)

EXTRA_SCRIPTS=(
    'gh-install.sh'
    'ghostty-install.sh'
    "homebrew-install.sh"
)

TO_INSTALL=("${CORE_SCRIPTS[@]}")

while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -h | --help)
        echo "Usage: dependencies-install-all.sh [OPTIONS]"
        echo
        echo "Options:"
        echo "  -h, --help            Show this help"
        echo "  -a, --all             Include all extras"
        echo "  -g, --github          Include github"
        echo "  -G, --ghostty         Include ghostty"
        exit 0
        ;;
    -a | --all)
        TO_INSTALL+=("${EXTRA_SCRIPTS[@]}")
        ;;
    -g | --github)
        TO_INSTALL+=("gh-install.sh")
        ;;
    -G | --ghostty)
        TO_INSTALL+=("ghostty-install.sh")
        ;;
    esac
    shift
done

for SCRIPT_FILENAME in "${TO_INSTALL[@]}"; do
    bash "$DEPENDENCIES_SCRIPTS_FOLDER/$SCRIPT_FILENAME"
done
