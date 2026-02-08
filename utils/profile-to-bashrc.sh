#!/usr/bin/env bash

if [[ ! $(grep '$HOME/.my-profile/__init__.sh' "$HOME"/.bashrc) ]]; then
    echo '. "$HOME/.my-profile/__init__.sh"' >>"$HOME"/.bashrc
fi
