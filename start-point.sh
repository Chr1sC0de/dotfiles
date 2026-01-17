#!/usr/bin/env bash

sudo apt-get install git -y
cd "$HOME" || exit 1
mkdir -p GitHub
cd GitHub || exit 1
git clone https://github.com/Chr1sC0de/dotfiles.git
cd dotfiles || exit 1
./install-all.sh
