#!/usr/bin/env bash
grep "$HOME/.my-profile/__init__.sh" "$HOME"/.bashrc

if [[ ! $(grep "$HOME/.my-profile/__init__.sh" "$HOME"/.bashrc) ]]; then
    echo '. "$HOME/.my-profile/__init__.sh"' >>"$HOME"/.bashrc
fi
