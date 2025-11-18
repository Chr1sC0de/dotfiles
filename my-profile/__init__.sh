#! /bin/bash

: '
Source this from the .bashrc file not the .profile file
as it will cause an error
'

# shellcheck disable=SC1091
. "$HOME/.my-profile/variables.sh"
. "$PROFILE_FOLDER/utils/__init__.sh"

if [[ -d $PROFILE_FOLDER/private-variables ]]; then
    . "$PROFILE_FOLDER/private-variables/__init__.sh"
fi

. "$PROFILE_FOLDER/nvm.sh"
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

# ---------------------------------------------------------------------------- #
#                                  setup path                                  #
# ---------------------------------------------------------------------------- #

export PATH="$PATH:/opt/nvim-linux-x86_64/bin"
export EDITOR=nvim
export VISUAL=nvim
export MANPAGER="nvim -c 'Man!' -"

# if type fastfetch >/dev/null; then
#     fastfetch
# fi
