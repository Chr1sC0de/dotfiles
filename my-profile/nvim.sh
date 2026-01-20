#!/usr/bin/env bash

export NVIM_CONFIG=$HOME/.config/nvim

nvim_path=/opt/nvim-linux-x86_64/bin

if [[ $PATH != *"$nvim_path"* ]]; then
    export PATH="$PATH":$nvim_path
fi

if [[ $IN_NEOVIM_TERMINAL ]]; then
    if ! (type nvr &>/dev/null); then
        # https://github.com/mhinz/neovim-remote
        if (type uv &>/dev/null); then
            uv tool install neovim-remote
        fi
    fi
    alias nvim="nvr"
fi

if type direnv &>/dev/null; then
    eval "$(direnv hook bash)"
fi

if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
