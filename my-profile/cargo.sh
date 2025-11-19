#!/usr/bin/env bash

: '
setup cargo env
'

CARGO_ENV="$HOME/.cargo/env"

#shellcheck disable=SC1090
if [[ -f $CARGO_ENV ]]; then
    if [[ ! grep '$HOME/.cargo/env'  "$HOME/.bashrc" ]]; then
        . "$CARGO_ENV"
    fi
fi
