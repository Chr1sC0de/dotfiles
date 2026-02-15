#!/usr/bin/env bash

: '
Setup for eza
'

if type eza &>/dev/null; then
    alias ls='eza'
    alias ll='eza -l'
    alias la='eza -a'
else
    alias ll='ls -l'
    alias la='ls -la'
fi
