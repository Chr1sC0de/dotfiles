#!/usr/bin/env bash

dependencies=(
    "git"
    "curl"
    "wget"
    "ca-certificates"
    "bat"
    "unzip"
    "ripgrep"
    "fd-find"
    "build-essential"
    "libclang-dev"
    "cmake"
    "gettext"
    "libtool"
    "libtool-bin"
    "pkg-config"
    "openssh-server"
    "python3"
    "python3-pip"
    "python3-venv"
    "tmux"
    "sudo"
)

if [[ $EUID -ne 0 ]]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${dependencies[@]}"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${dependencies[@]}"
fi

if [[ $EUID -ne 0 ]]; then
    sudo apt-get autoremove -y
else
    apt-get autoremove -y
fi

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
