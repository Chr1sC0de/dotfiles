#!/usr/bin/env bash

set -ue

while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -h | --help)
        echo "Usage: clone-worktree.sh [OPTIONS] [URL]"
        ;;
    *)
        URL=$1
        ;;
    esac
    shift
done

BASENAME=${URL##*/}
NAME=${2:-${BASENAME%.*}}

echo "url=$URL"
echo "basename=$BASENAME"
echo "reponame=$NAME"

mkdir -p "$NAME"

cd "$NAME"

git clone --bare "$URL" "$NAME.worktree"

cd "$NAME"

echo "gitdir: ." >.git

git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

git fetch origin

cd ..
