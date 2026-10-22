#!/usr/bin/env -S bash

. "utils/common.sh"

FORCE=false
export VERBOSE=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -h | --help)
        echo "Usage: utils/symlink-create.sh [OPTIONS] [TARGET]"
        echo "create symbolic links for the following valid targets"
        for LINK in "${DOTNAMES[@]}"; do
            echo "  $LINK"
        done
        echo "Options:"
        echo "  -h, --help        display this message"
        echo "  -f, --force       replace conflicting symlinks only"
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

resolve_target "$TARGET" || exit 1
if link_matches; then
    echoinfo "Correct link already exists: $LINK_DESTINATION"
    exit 0
fi
if [[ -L $LINK_DESTINATION ]]; then
    if ! $FORCE; then
        printf 'Conflicting symlink: %s (use --force to replace)\n' "$LINK_DESTINATION" >&2
        exit 1
    fi
    rm -- "$LINK_DESTINATION"
elif [[ -e $LINK_DESTINATION ]]; then
    printf 'Conflicting file or directory: %s\n' "$LINK_DESTINATION" >&2
    exit 1
fi
mkdir -p -- "$(dirname -- "$LINK_DESTINATION")"
ln -svT -- "$LINK_SOURCE" "$LINK_DESTINATION"
