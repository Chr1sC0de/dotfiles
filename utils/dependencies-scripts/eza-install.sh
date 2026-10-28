#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 https://github.com/eza-community/eza/releases/download/v0.23.5/eza_x86_64-unknown-linux-gnu.tar.gz -o "$tmp/eza.tar.gz"
tar -xzf "$tmp/eza.tar.gz" -C "$tmp"
mkdir -p "$HOME/.local/bin"
install -m 755 "$tmp/eza" "$HOME/.local/bin/eza"
