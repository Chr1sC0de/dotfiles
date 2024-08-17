#! /bin/bash

set -e

url=$1
basename=${url##*/}
name=${2:-${basename%.*}}

echo "url=$url"
echo "basename=$basename"
echo "reponame=$name"

mkdir $name
cd "$name" || exit

git clone --bare $url .root
cd .root
echo "gitdir: ." > .git

git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

git fetch origin

cd ..
