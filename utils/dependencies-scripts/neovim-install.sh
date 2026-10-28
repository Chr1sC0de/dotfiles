#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz -o "$tmp/nvim.tar.gz"
tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"
if ((EUID == 0)); then
    rm -rf /opt/nvim-linux-x86_64
    mv "$tmp/nvim-linux-x86_64" /opt/nvim-linux-x86_64
else
    mkdir -p "$HOME/.local"
    cp -a "$tmp/nvim-linux-x86_64/." "$HOME/.local/"
fi
