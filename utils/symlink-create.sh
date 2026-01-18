#!/usr/bin/env -S bash -x

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

. "$SCRIPT_DIR/common.sh"

FORCE=false
export VERBOSE=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -h | --help)
        echo "Usage: create-symlink.sh [OPTIONS] [TARGET]"
        echo "create symbolic links for the following valid targets"
        for LINK in "${DOTNAMES[@]}"; do
            echo "  $LINK"
        done
        echo "Options:"
        echo "  -h, --help        display this message"
        echo "  -f, --force       forcibly remove symlink if exists"
        echo "  -v, --verbose     show logs"
        exit 0
        ;;
    -f | --force)
        FORCE=true
        ;;
    -v | --verbose)
        VERBOSE=true
        ;;
    *)
        if [[ -z $TARGET ]]; then
            TARGET=$1
        fi
        ;;
    esac
    shift
done

set -e

if [[ -z $TARGET ]]; then
    echoinfo "No input provided, skipping"
    exit 1
fi

COLORDOTNAME="\e[36m$TARGET\e[0m"

if [[ ! ${DOTNAMES[*]} =~ $TARGET ]]; then
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

SYMLINK_TARGET="$HOME/.$TARGET"

if [[ ! -L $SYMLINK_TARGET ]]; then
    echoinfo "$COLORDOTNAME symlink not found, creating"
    ln -s -v "$DOTFILE_DIR/$TARGET" "$SYMLINK_TARGET"
    echoinfo "Finished creating $COLORDOTNAME symlink"
elif $FORCE; then
    echoinfo "Forcefully creating symlink"
    rm -f "$SYMLINK_TARGET"
    ln -s -v "$DOTFILE_DIR/$TARGET" "$SYMLINK_TARGET"
    echoinfo "Finished creating $COLORDOTNAME symlink"
else
    echoinfo "$COLORDOTNAME symlink already exists, skipping"
fi
