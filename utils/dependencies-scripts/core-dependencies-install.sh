#!/usr/bin/env bash
set -euo pipefail

dependencies=(git curl ca-certificates build-essential cmake python3 tmux)
case ${DOTFILES_CORE_SOURCE:-binaries} in
apt) dependencies+=(jq bat ripgrep fd-find) ;;
binaries) ;;
*)
	echo 'DOTFILES_CORE_SOURCE must be apt or binaries' >&2
	exit 2
	;;
esac
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$script_dir/../apt-install-missing.sh" "${dependencies[@]}"
mkdir -p "$HOME/.local/bin"
if [[ ${DOTFILES_CORE_SOURCE:-binaries} == binaries ]]; then
	bash "$script_dir/core-binaries-install.sh"
else
	if type fdfind &>/dev/null; then
		ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
	fi
	if type batcat &>/dev/null; then
		ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
	fi
fi
if [[ ! -d $HOME/.fzf/.git ]]; then
	git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
fi
"$HOME/.fzf/install" --all --no-bash
if [[ ! -d $HOME/.tmux/plugins/tpm/.git ]]; then
	git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi
