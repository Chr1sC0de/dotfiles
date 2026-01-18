#!/usr/bin/env -S bash -x

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
git clone https://github.com/Chr1sC0de/dotfiles.git
cd dotfiles || exit 1

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

UTILS_DIR="$SCRIPT_DIR/utils"

bash "$UTILS_DIR/dependencies-install-all.sh"
bash "$UTILS_DIR/dotfiles-install.sh" -f --tmux
bash "$UTILS_DIR/profile-to-bashrc.sh"

. "$HOME/.bashrc"
