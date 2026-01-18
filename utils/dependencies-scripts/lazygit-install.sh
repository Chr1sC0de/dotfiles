#!/usr/bin/env bash

tag=v0.58.1 && echo "tag=$tag"
owner=jesseduffield && echo "owner=$owner"
repo=lazygit && echo "repo=$repo"
binary_name=lazygit && echo "binary_name=$binary_name"
download_file=lazygit_0.58.1_linux_x86_64.tar.gz && echo "download_file=$download_file"
release="https://github.com/$owner/$repo/releases/download/$tag/$download_file" && echo "release=$release"

download_folder=/tmp && echo "download_folder=$download_folder"
downloaded_file=$download_folder/$download_file && echo downloaded_file=$downloaded_file

extract_folder=$download_folder/$repo && echo extract_folder=$extract_folder
extracted_binary=$extract_folder/$binary_name && echo extracted_binary=$extracted_binary

target_folder=$HOME/.local/bin && echo target_folder="$target_folder"
target_file=$target_folder/$binary_name && echo target_file="$target_file"

echo setting up $repo release $release to /tmp
wget -P /tmp $release

echo extracting $downloaded_file to $extract_folder
mkdir -p $extract_folder
tar -xvzf $downloaded_file -C $extract_folder

echo moving $extracted_binary to "$target_file"
mv -f "$extracted_binary" "$target_file"

rm -rf $downloaded_file
rm -rf $extract_folder
