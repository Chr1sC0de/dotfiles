#!/bin/bash

: '
setup cargo env
'

CARGO_ENV="$HOME/.cargo/env"

#shellcheck disable=SC1090
if [[ -f $CARGO_ENV ]]; then
    . "$CARGO_ENV"
fi
