#!/usr/bin/env -S bash -x

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

. "$SCRIPT_DIR/common.sh"

TO_INSTALL=("${DEFAULTS[@]}")
SYMLINK_CREATE_KWARGS=()

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help)
        echo "Usage: install-dotfiles.sh [OPTIONS]"
        echo
        echo "Options:"
        echo "  -h, --help            Show this help"
        echo "  -a, --all             Include all extras"
        echo "  -k, --kitty           Include kitty config"
        echo "  -t, --tmux            Include tmux config"
        echo "  -g, --gitconfig       Include gitconfig"
        echo "  -x, --xdg-terminals   Include xdg-terminals config"
        echo "  -v, --verbose         show logs"
        echo "  -f, --force           force install symlink"
        exit 0
        ;;
    -k | --kitty)
        TO_INSTALL+=("config/kitty")
        ;;
    -t | --tmux)
        TO_INSTALL+=("tmux.conf")
        ;;
    -g | --gitconfig)
        TO_INSTALL+=("gitconfig")
        ;;
    -x | --xdg-terminals)
        TO_INSTALL+=("config/xdg-terminals.list")
        ;;
    -v | --verbose)
        SYMLINK_CREATE_KWARGS+=("-v")
        ;;
    -f | --force)
        SYMLINK_CREATE_KWARGS+=("-f")
        ;;
    -a | --all)
        TO_INSTALL+=("${EXTRAS[@]}")
        ;;
    esac
    shift
done

for INSTALL in "${TO_INSTALL[@]}"; do
    "$SCRIPT_DIR"/"symlink-create.sh" "$INSTALL" "${SYMLINK_CREATE_KWARGS[@]}"
done
