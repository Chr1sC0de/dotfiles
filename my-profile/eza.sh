#!/usr/bin/env bash

: '
Setup for eza
'

if type eza &>/dev/null; then
    alias ls='eza --header'
    alias ll='eza -l --header'
    alias la='eza -la --header'
    alias lat='eza -la --total-size --header'
    alias llt='eza -l --total-size --header'
    alias lal='eza -la --loc --header'
    alias lll='eza -l --loc --header'
else
    alias ll='ls -l'
    alias la='ls -la'
fi
