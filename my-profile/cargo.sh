#!/usr/bin/env bash

: '
setup cargo env
'

CARGO_ENV="$HOME/.cargo/env"

#shellcheck disable=SC1090
if [[ -f $CARGO_ENV ]]; then
    if (! grep "$CARGO_ENV" "$HOME/.bashrc"); then
        echo "setup cargo env"
        . "$CARGO_ENV"
    fi
fi
