#!/usr/bin/env bash

sudo apt install git openssh-server

mkdir -p GitHub

cd GitHub || exit

git glone https://github.com/Chr1sC0de/dotfiles.git
