#! /bin/bash

set -e

URL=$1
BASENAME=${URL##*/}
NAME=${2:-${BASENAME%.*}}

echoinfo "url=$URL"
echoinfo "basename=$BASENAME"
echoinfo "reponame=$NAME"

mkdir "$NAME"
cd "$NAME" || exit

git clone --bare "$URL" .root
cd .root
echo "gitdir: ." >.git

git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

git fetch origin

cd ..
