#!/usr/bin/env bash
# Run from any directory. Results default to /tmp/opencode/install-audit.
# Functions are invoked indirectly; bash -c expands variables as the target user.
# shellcheck disable=SC2329,SC2016
set -euo pipefail

if [[ ${1:-} == --inside ]]; then
	export DEBIAN_FRONTEND=noninteractive
	mkdir -p /results
	printf 'stage\tseconds\tstatus\n' >/results/timings.tsv
	stage() {
		local name=$1 start=$SECONDS status=0
		shift
		"$@" >"/results/$name.log" 2>&1 || status=$?
		printf '%s\t%s\t%s\n' "$name" "$((SECONDS - start))" "$status" | tee -a /results/timings.tsv
		return "$status"
	}
	stage bootstrap bash /source/utils/apt-install-missing.sh git curl ca-certificates sudo
	home=/root
	runner=()
	if [[ $AUDIT_USER == user ]]; then
		useradd -m -s /bin/bash audit
		printf 'audit ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/audit
		home=/home/audit
		runner=(sudo -H -u audit)
	fi
	cp -a /source "$home/.dotfiles"
	if [[ $AUDIT_USER == user ]]; then
		chown -R audit:audit "$home/.dotfiles"
	fi
	run_script() {
		"${runner[@]}" env DOTFILES_CORE_SOURCE="$DOTFILES_CORE_SOURCE" bash -c 'cd "$HOME/.dotfiles"; export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"; bash "$@"' bash "$@"
	}
	scripts=(core-dependencies-install gh-install)
	binaries=(git curl jq bat rg fd tmux cmake python3 gh)
	if [[ $AUDIT_SCOPE == full ]]; then
		scripts+=(rust-install cargo-binstall nvm-install uv-install grip-grab-install eza-install neovim-install direnv-install lazygit-install starship-install duckdb-install treesitter-cli zoxide)
		binaries+=(nvim eza lazygit uv cargo)
	fi
	failed=0
	for pass in 1 2; do
		if [[ $pass == 2 ]]; then
			# Fail the repeat pass if any installer attempts APT, including via sudo.
			printf '#!/bin/sh\necho "Unexpected APT on repeat install" >&2\nexit 99\n' >/usr/local/bin/apt-get
			chmod +x /usr/local/bin/apt-get
		fi
		for script in "${scripts[@]}"; do
			stage "$pass-$script" run_script "utils/dependencies-scripts/$script.sh" || failed=1
		done
		if [[ $AUDIT_SCOPE == full ]]; then
			stage "$pass-dotfiles" run_script utils/dotfiles-install.sh -f --tmux || failed=1
			stage "$pass-profile" run_script utils/profile-to-bashrc.sh || failed=1
		fi
	done
	dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' >/results/packages.tsv
	stage smoke "${runner[@]}" bash -c '
        set -euo pipefail
        export PATH="$HOME/.local/bin:/opt/nvim-linux-x86_64/bin:$HOME/.cargo/bin:$PATH"
        for binary in "$@"; do
            command -v "$binary"
            flag=--version
            [[ $binary != tmux ]] || flag=-V
            "$binary" "$flag"
        done
        printf "{\"ok\":true}\n" | jq -e .ok
        printf "audit-probe\n" | rg audit-probe
        fd --max-depth 1 . "$HOME"
        printf "audit-probe\n" | bat --plain --paging=never
        tmux -L audit new-session -d
        tmux -L audit kill-server
    ' bash "${binaries[@]}" || failed=1
	exit "$failed"
fi

engine=${CONTAINER_ENGINE:-podman}
image=${AUDIT_IMAGE:-docker.io/library/debian:13-slim}
user=${AUDIT_USER:-root}
source=${DOTFILES_CORE_SOURCE:-binaries}
scope=${AUDIT_SCOPE:-full}
[[ $user == root || $user == user ]] || {
	echo 'AUDIT_USER must be root or user' >&2
	exit 2
}
[[ $source == apt || $source == binaries ]] || {
	echo 'DOTFILES_CORE_SOURCE must be apt or binaries' >&2
	exit 2
}
[[ $scope == core || $scope == full ]] || {
	echo 'AUDIT_SCOPE must be core or full' >&2
	exit 2
}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
results=${AUDIT_RESULTS:-/tmp/opencode/install-audit/$(date +%Y%m%d-%H%M%S)-$user-$source-$scope}
mkdir -p "$results"
printf 'image=%s\nuser=%s\nsource=%s\nscope=%s\ncommit=%s\n' "$image" "$user" "$source" "$scope" "$(git -C "$root" rev-parse HEAD)" >"$results/metadata.txt"
git -C "$root" diff >"$results/working-tree.diff"
name="dotfiles-audit-$$"
cleanup() { "$engine" rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
"$engine" create --name "$name" -e AUDIT_USER="$user" -e DOTFILES_CORE_SOURCE="$source" -e AUDIT_SCOPE="$scope" "$image" sleep infinity >/dev/null
"$engine" image inspect "$image" >"$results/image.json"
"$engine" start "$name" >/dev/null
"$engine" exec "$name" mkdir -p /source
tar -C "$root" --exclude=.git -cf - . | "$engine" cp - "$name:/source"
status=0
"$engine" exec "$name" bash /source/tests/install_debian_audit.sh --inside || status=$?
"$engine" cp "$name:/results/." "$results/"
printf 'Audit results: %s (exit %s)\n' "$results" "$status"
exit "$status"
