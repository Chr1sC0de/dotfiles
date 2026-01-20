#!/usr/bin/env bash

cargo_env="$HOME/.cargo/env"

#shellcheck disable=SC1090
if [[ -f $cargo_env ]]; then
    if (! grep "$cargo_env" "$HOME/.bashrc"); then
        echo "setup cargo env"
        . "$cargo_env"
    fi
fi
