#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz

    tag=latest && echo "tag=$tag"
    owner=neovim && echo "owner=$owner"
    repo=neovim && echo "repo=$repo"
    download_file=nvim-linux-x86_64.tar.gz && echo "download_file=$download_file"
    release="https://github.com/$owner/$repo/releases/$tag/download/$download_file" && echo "release=$release"

    download_folder=/tmp && echo "download_folder=$download_folder"
    downloaded_file=$download_folder/$download_file && echo downloaded_file=$downloaded_file

    extract_folder=$download_folder/$repo && echo extract_folder=$extract_folder
    extracted_files=$extract_folder/nvim-linux-x86_64

    target_folder=$HOME/.local && echo target_folder="$target_folder"

    echo setting up $repo release "$release" to /tmp
    wget -P /tmp "$release"

    echo extracting $downloaded_file to $extract_folder
    mkdir -p $extract_folder
    tar -xvzf $downloaded_file -C $extract_folder

    echo moving files "$extracted_files" to "$target_folder"
    cp -afr $extracted_files/* "$HOME/.local"

    rm -rf $downloaded_file
    rm -rf $extract_folder
else
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    rm -rf /opt/nvim-linux-x86_64
    tar -C /opt -xzf nvim-linux-x86_64.tar.gz
    rm nvim-linux-x86_64.tar.gz
fi
