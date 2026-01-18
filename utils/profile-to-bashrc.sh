#!/usr/bin/env -S bash -x
grep "$HOME/.my-profile/__init__.sh" "$HOME"/.bashrc

if [[ ! $(grep "$HOME/.my-profile/__init__.sh" "$HOME"/.bashrc) ]]; then
    echo '. "$HOME/.my-profile/__init__.sh"' >>"$HOME"/.bashrc
fi
