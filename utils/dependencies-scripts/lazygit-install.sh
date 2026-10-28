#!/usr/bin/env bash
set -euo pipefail
version=0.64.0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 "https://github.com/jesseduffield/lazygit/releases/download/v$version/lazygit_${version}_linux_x86_64.tar.gz" -o "$tmp/lazygit.tar.gz"
tar -xzf "$tmp/lazygit.tar.gz" -C "$tmp"
mkdir -p "$HOME/.local/bin"
install -m 755 "$tmp/lazygit" "$HOME/.local/bin/lazygit"
