#!/usr/bin/env bash

set -ue

while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -h | --help)
        echo "Usage: clone-worktree.sh [OPTIONS] [URL]"
        ;;
    esac
    shift
done

URL=$1
BASENAME=${URL##*/}
NAME=${2:-${BASENAME%.*}}

echo "url=$URL"
echo "basename=$BASENAME"
echo "reponame=$NAME"

git clone --bare "$URL" "$NAME"
cd "$NAME"
echo "gitdir: ." >.git

git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

git fetch origin

cd ..
