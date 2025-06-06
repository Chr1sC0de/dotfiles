#! /bin/bash

: '
Source this from the .bashrc file not the .profile file
as it will cause an error
'

# shellcheck disable=SC1091
source "$HOME/.my-profile/variables.sh"
source "$PROFILE_FOLDER/utils/__init__.sh"

if [[ -d $PROFILE_FOLDER/private-variables ]]; then
    source "$PROFILE_FOLDER/private-variables/__init__.sh"
fi

source "$PROFILE_FOLDER/nvm.sh"
source "$PROFILE_FOLDER/starship.sh"
source "$PROFILE_FOLDER/fzf.sh"
source "$PROFILE_FOLDER/eza.sh"
source "$PROFILE_FOLDER/popos_fast_switching.sh"
source "$PROFILE_FOLDER/texlive.sh"

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

# if type fastfetch >/dev/null; then
#     fastfetch
# fi
