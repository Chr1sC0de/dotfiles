#!/usr/bin/env bash

sudo apt update -y;

sudo apt install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    bat \
    unzip \
    ripgrep \
    fd-find \
    build-essential \
    cmake \
    gettext \
    libtool \
    libtool-bin \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    sudo ;

if type fdfind &> /dev/null; then
    ln -sf "$(which fdfind)" $HOME/.local/bin/fd
fi

if type batcat &> /dev/null; then
    ln -sf "$(which batcat)" $HOME/.local/bin/bat
fi

sudo apt autoremove -y;

git clone --depth 1 https://github.com/junegunn/fzf.git $HOME/.fzf
$HOME/.fzf/install --all --no-bash 
