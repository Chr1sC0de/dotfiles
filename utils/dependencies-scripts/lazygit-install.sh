#!/usr/bin/env bash

tag=v0.58.1
owner=jesseduffield
repo=lazygit
binary_name=lazygit
download_file=lazygit_0.58.1_linux_x86_64.tar.gz
release="https://github.com/$owner/$repo/releases/download/$tag/$download_file"

download_folder=/tmp
downloaded_file=$download_folder/$download_file

extract_folder=$download_folder/$repo
extracted_binary=$extract_folder/$binary_name

target_folder=$HOME/.local/bin
target_file=$target_folder/$binary_name

echo setting up $repo release $release to /tmp
wget -P /tmp $release

echo extracting $downloaded_file to $extract_folder
mkdir -p $extract_folder
tar -xvzf $downloaded_file -C $extract_folder

echo moving $extracted_binary to "$target_file"
mv -f "$extracted_binary" "$target_file"

rm -rf $downloaded_file
rm -rf $extract_folder
