#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

# install core components
if [[ $EUID -ne 0 ]]; then
	sudo apt-get update -y
	sudo apt-get install git curl wget -y
else
	apt-get update -y
	apt-get install git curl wget -y
fi

cd "$HOME" || exit 1
git clone https://github.com/Chr1sC0de/dotfiles.git .dotfiles
cd .dotfiles || exit 1

bash "utils/dependencies-install-all.sh"
bash "utils/dotfiles-install.sh" -f --tmux
bash "utils/profile-to-bashrc.sh"

. "$HOME/.bashrc"
