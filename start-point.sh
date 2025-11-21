#!/usr/bin/env bash

sudo apt install git -y

cd "$HOME" || exit

mkdir -p GitHub

cd GitHub || exit

git clone https://github.com/Chr1sC0de/dotfiles.git

cd dotfiles || exit
