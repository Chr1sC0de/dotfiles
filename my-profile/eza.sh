#!/bin/bash

: '
Setup for eza
'

if type eza &>/dev/null; then
    alias ls='eza'
    alias ll='eza -l'
else
    alias ll='ls -l'
fi
