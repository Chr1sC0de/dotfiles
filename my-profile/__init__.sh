#!/usr/bin/env bash

: '
Source this from the .bashrc file not the .profile file
as it will cause an error
'

if [[ $PATH != *"/opt/nvim-linux-x86_64/bin"* ]]; then
    export PATH="$PATH:/opt/nvim-linux-x86_64/bin"
fi

# set PATH so it includes user's private bin if it exists
if [[ $PATH != *"$HOME/.local/bin"* ]]; then
    PATH="$HOME/.local/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [[ $PATH != *"$HOME/bin"* ]]; then
    PATH="$HOME/bin:$PATH"
fi

# set LD_LIBRARY_PATH so it includes user's private lib if it exists
if [[ $LD_LIBRARY_PATH != *"$HOME/.local/lib"* ]]; then
    LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"
fi

# source fzf
if [[ ! "$PATH" == *"$HOME/.fzf/bin"* ]]; then
    PATH="${PATH:+${PATH}:}$HOME/.fzf/bin"
    eval "$(fzf --bash)"
fi

# shellcheck disable=SC1091
. "$HOME/.my-profile/variables.sh"
. "$PROFILE_FOLDER/utils/__init__.sh"

if [[ -d $PROFILE_FOLDER/private-variables ]]; then
    . "$PROFILE_FOLDER/private-variables/__init__.sh"
fi

. "$PROFILE_FOLDER/starship.sh"
. "$PROFILE_FOLDER/fzf.sh"
. "$PROFILE_FOLDER/eza.sh"
. "$PROFILE_FOLDER/popos_fast_switching.sh"
. "$PROFILE_FOLDER/texlive.sh"

# disable ctrl+s in terminal
stty -ixon

# ---------------------------------------------------------------------------- #
#                                  setup alias                                 #
# ---------------------------------------------------------------------------- #

alias clip="xclip -selection c"
alias fdc="fd -d 1"
alias la="ls -la"
alias ll="ls -l"

# ---------------------------------------------------------------------------- #
#                                  setup path                                  #
# ---------------------------------------------------------------------------- #

export EDITOR=nvim
export VISUAL=nvim
export MANPAGER="nvim -c 'Man!' -"

# if type fastfetch >/dev/null; then
#     fastfetch
# fi

if [[ $IN_NEOVIM_TERMINAL ]]; then
    if ! (type nvr &>/dev/null); then
        # https://github.com/mhinz/neovim-remote
        uv tool install neovim-remote
    fi
    alias nvim="nvr"
fi

if type direnv &>/dev/null; then
    eval "$(direnv hook bash)"
fi

if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
