#!/usr/bin/env bash

(
    cd $HOME/Downloads/
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    tar -xzf nvim-linux-x86_64.tar.gz
    cp -afr nvim-linux-x86_64/* $HOME/.local
)
