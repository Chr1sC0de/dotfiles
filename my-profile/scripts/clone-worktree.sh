#! /bin/bash

set -e

URL=$1
BASENAME=${URL##*/}
NAME=${2:-${BASENAME%.*}}

echo "url=$URL"
echo "basename=$BASENAME"
echo "reponame=$NAME"

mkdir "$NAME"
cd "$NAME" || exit

git clone --bare "$URL" $NAME
cd $NAME
echo "gitdir: ." >.git

git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

git fetch origin

cd ..
