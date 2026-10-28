#!/usr/bin/env bash
# No APT operations when every requested package is already installed.
set -euo pipefail
missing=()
for package in "$@"; do
	if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) != 'install ok installed' ]]; then
		missing+=("$package")
	fi
done
if ((${#missing[@]} == 0)); then
	echo 'System dependencies already installed; skipping APT.'
	exit 0
fi
privilege=()
if ((EUID != 0)); then
	privilege=(sudo)
fi
if [[ ${DOTFILES_APT_UPDATED:-0} != 1 ]]; then
	"${privilege[@]}" apt-get update
fi
"${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
