#!/usr/bin/bash

: '
setup rye env
'

RYE_ENV="$HOME/.rye/env"

#shellcheck disable=SC1090
if [[ ! -f $RYE_ENV ]]; then
    source "$RYE_ENV"
fi
