#!/usr/bin/env bash

: '
Source this from the .bashrc file not the .profile file
as it will cause an error
'

# ---------------------------------------------------------------------------- #
#                             initial setup                                    #
# ---------------------------------------------------------------------------- #

# shellcheck disable=SC1091
. "$HOME/.my-profile/variables.sh"
. "$PROFILE_FOLDER/utils/__init__.sh"

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

if [[ -d $PROFILE_FOLDER/private-variables ]]; then
    # shellcheck disable=SC1091
    . "$PROFILE_FOLDER/private-variables/__init__.sh"
fi

. "$PROFILE_FOLDER/starship.sh"
. "$PROFILE_FOLDER/fzf.sh"
. "$PROFILE_FOLDER/nvim.sh"
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
#                                  setup vars                                  #
# ---------------------------------------------------------------------------- #

export EDITOR=nvim
export VISUAL=nvim
export MANPAGER="nvim -c 'Man!' -"
export TERM=xterm-256color
