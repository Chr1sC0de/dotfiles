#!/usr/bin/env bash

sudo apt-get install git -y
cd "$HOME" || exit
git clone https://github.com/Chr1sC0de/dotfiles.git .dotfiles
cd .dotfiles || exit
