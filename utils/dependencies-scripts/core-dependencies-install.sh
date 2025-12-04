#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

# install core components
sudo apt-get update -y

sudo apt-get install -y --no-install-recommends \
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
    openssh-server \
    python3 \
    python3-pip \
    python3-venv \
    tmux \
    sudo

sudo apt-get autoremove -y

mkdir -p "$HOME/.local/bin"

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

# install dependencies for tmux plugins
# now just press ctrl + leader r then `ctrl + leader I`
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
