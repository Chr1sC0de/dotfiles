#!/usr/bin/env bash

TEXLIVE_DIR="/usr/local/texlive/2024/bin/x86_64-linux"

if [[ -d $TEXLIVE_DIR ]]; then
    if [[ $PATH != *"$TEXLIVE_DIR"* ]]; then
        export PATH="$PATH:$TEXLIVE_DIR"
    fi
fi
