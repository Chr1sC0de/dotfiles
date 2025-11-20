#!/usr/bin/env bash

sudo apt install git openssh-server -y

mkdir -p GitHub

cd GitHub || exit

git clone https://github.com/Chr1sC0de/dotfiles.git
