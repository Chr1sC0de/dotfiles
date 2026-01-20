#!/usr/bin/env bash

texlive_dir="/usr/local/texlive/2024/bin/x86_64-linux"

if [[ -d $texlive_dir ]]; then
    if [[ $PATH != *"$texlive_dir"* ]]; then
        export PATH="$PATH:$texlive_dir"
    fi
fi
