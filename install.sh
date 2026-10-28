#!/usr/bin/env bash
set -e
export DEBIAN_FRONTEND=noninteractive

# This bootstrap runs before the repository's shared APT helper is available.
missing=()
for package in git curl ca-certificates; do
	if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) != 'install ok installed' ]]; then
		missing+=("$package")
	fi
done
if ((${#missing[@]})); then
	privilege=()
	if ((EUID != 0)); then
		privilege=(sudo)
	fi
	"${privilege[@]}" apt-get update
	"${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
	export DOTFILES_APT_UPDATED=1
fi

cd "$HOME"
if [[ ! -d .dotfiles/.git && ! -f .dotfiles/.git ]]; then
	git clone --depth 1 https://github.com/Chr1sC0de/dotfiles.git .dotfiles
fi
cd .dotfiles
bash utils/dependencies-install-all.sh
bash utils/dotfiles-install.sh -f --tmux
bash utils/profile-to-bashrc.sh

# Shell initialization may contain interactive-only commands.
set +e
. "$HOME/.bashrc"
