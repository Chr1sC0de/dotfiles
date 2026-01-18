#!/usr/bin/env bash

tag=v0.23.4
file=eza_x86_64-unknown-linux-gnu.tar.gz
repository=eza-community/eza
release="https://github.com/$repository/releases/download/$tag/$file"

source_file=/tmp/eza
target_file="$HOME"/.local/bin/eza

echo setting up eza release $release to /tmp
wget -P /tmp $release

(cd /tmp && tar -xvzf $file || exit)

echo moving $source_file to "$target_file"

mv -f $source_file "$target_file"
