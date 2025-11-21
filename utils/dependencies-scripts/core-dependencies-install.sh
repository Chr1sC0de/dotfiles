#!/usr/bin/env bash

# install core components
sudo apt update -y

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
    sudo
# python3 \
# python3-pip \
# python3-venv \

sudo apt autoremove -y

# create symbolic link fo fdfind
if type fdfind &>/dev/null; then
    ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
fi

# create symbolic link for bash
if type batcat &>/dev/null; then
    ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
fi

# install fzf
git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"

"$HOME/.fzf/install" --all --no-bash
