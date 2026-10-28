#!/usr/bin/env bash
set -euo pipefail
version=2.103.3
case $(uname -m) in
x86_64)
	arch=amd64
	checksum=4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d
	;;
aarch64 | arm64)
	arch=arm64
	checksum=ee32df2323c8847f5fac6cb6b4b69ca75828e9329a8f22f677021f7b3306ce63
	;;
*)
	echo 'Unsupported GitHub CLI architecture' >&2
	exit 1
	;;
esac
bin="$HOME/.local/bin"
if [[ -x $bin/gh ]] && [[ $("$bin/gh" --version) == "gh version $version "* ]]; then
	echo "gh $version already installed"
	exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
archive="gh_${version}_linux_$arch"
curl -fsSL --retry 3 "https://github.com/cli/cli/releases/download/v$version/$archive.tar.gz" -o "$tmp/gh.tar.gz"
printf '%s  %s\n' "$checksum" "$tmp/gh.tar.gz" | sha256sum --check -
tar -xzf "$tmp/gh.tar.gz" -C "$tmp"
mkdir -p "$bin"
install -m 755 "$tmp/$archive/bin/gh" "$bin/gh"
"$bin/gh" --version
