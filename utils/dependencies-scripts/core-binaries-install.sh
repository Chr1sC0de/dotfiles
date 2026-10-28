#!/usr/bin/env bash
# Official upstream releases; keep the APT path available for comparison.
set -euo pipefail
case $(uname -m) in
x86_64)
	arch=x86_64
	jq_arch=amd64
	;;
aarch64 | arm64)
	arch=aarch64
	jq_arch=arm64
	;;
*)
	echo 'Unsupported release-binary architecture' >&2
	exit 1
	;;
esac
bin="$HOME/.local/bin"
mkdir -p "$bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
install_release() {
	local name=$1 version=$2 repository=$3 asset=$4 executable=$5
	local directory="$tmp/$name" installed expected="${2#v}"
	expected=${expected#jq-}
	if [[ -x $bin/$name ]]; then
		installed=$("$bin/$name" --version | head -1)
		installed=${installed#jq-}
		installed=${installed#* }
		installed=${installed%% *}
		if [[ $installed == "$expected" ]]; then
			printf '%s %s already installed\n' "$name" "$version"
			return
		fi
	fi
	mkdir -p "$directory"
	curl --fail --location --retry 3 --silent --show-error \
		"https://github.com/$repository/releases/download/$version/$asset" -o "$directory/archive"
	if [[ $name == jq ]]; then
		install -m 755 "$directory/archive" "$directory/$name"
	else
		tar -xzf "$directory/archive" -C "$directory"
		install -m 755 "$directory/$executable" "$directory/$name"
	fi
	"$directory/$name" --version
	# Remove old fd/bat compatibility links rather than overwriting system targets.
	rm -f "$bin/$name"
	install -m 755 "$directory/$name" "$bin/$name"
}
pids=()
install_release jq jq-1.7.1 jqlang/jq "jq-linux-$jq_arch" jq &
pids+=("$!")
install_release bat v0.25.0 sharkdp/bat "bat-v0.25.0-$arch-unknown-linux-gnu.tar.gz" "bat-v0.25.0-$arch-unknown-linux-gnu/bat" &
pids+=("$!")
install_release fd v10.2.0 sharkdp/fd "fd-v10.2.0-$arch-unknown-linux-gnu.tar.gz" "fd-v10.2.0-$arch-unknown-linux-gnu/fd" &
pids+=("$!")
rg_target="$arch-unknown-linux-gnu"
[[ $arch != x86_64 ]] || rg_target=x86_64-unknown-linux-musl
install_release rg 14.1.1 BurntSushi/ripgrep "ripgrep-14.1.1-$rg_target.tar.gz" "ripgrep-14.1.1-$rg_target/rg" &
pids+=("$!")
status=0
for pid in "${pids[@]}"; do
	wait "$pid" || status=1
done
exit "$status"
