#!/usr/bin/env -S bash -x

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# import the DOTFILE_DIR variable, echoinfo function, DOTNAMES
. "$SCRIPT_DIR/common.sh"

if [[ -z $1 ]]; then
    echoinfo "No input provided, skipping"
    exit 1
fi

DOTNAME="$1"
COLORDOTNAME="\e[36m$DOTNAME\e[0m"

if [[ ! ${DOTNAMES[*]} =~ $DOTNAME ]]; then
    echoinfo "$COLORDOTNAME not in available dotfiles\e[36m"
    echo "["
    for NAME in "${DOTNAMES[@]}"; do
        echo "  $NAME"
    done
    echo "]"
    echoinfo "Input dotfile name should not start with ."
    exit 1
fi

echoinfo "Removing symlink for $COLORDOTNAME"

SYMLINK_TARGET="$HOME/.$DOTNAME"

if [[ -L $SYMLINK_TARGET ]]; then
    echoinfo "$COLORDOTNAME symlink found, removing"
    rm "$SYMLINK_TARGET"
    echoinfo "Finished removing $COLORDOTNAME symlink"
else
    echoinfo "$COLORDOTNAME s not found"
fi
