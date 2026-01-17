#!/usr/bin/env -S bash -x

sudo apt-get install git -y
cd "$HOME" || exit 1
mkdir -p GitHub
cd GitHub || exit 1
git clone https://github.com/Chr1sC0de/dotfiles.git
cd dotfiles || exit 1

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

UTILS_DIR="$SCRIPT_DIR/utils"

bash "$UTILS_DIR/dependencies-install-all.sh"
bash "$UTILS_DIR/dotfiles-install.sh" -f --tmux
bash "$UTILS_DIR/profile-to-bashrc.sh"

. "$HOME/.bashrc"
