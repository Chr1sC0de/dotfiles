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

source "$PROFILE_FOLDER/rye.sh"
source "$PROFILE_FOLDER/nvm.sh"
source "$PROFILE_FOLDER/starship.sh"
source "$PROFILE_FOLDER/fzf.sh"
source "$PROFILE_FOLDER/eza.sh"

# disable ctrl+s in terminal
stty -ixon

# ---------------------------------------------------------------------------- #
#                                  setup alias                                 #
# ---------------------------------------------------------------------------- #

alias clip="xclip -selection c"
alias fdc="fd -d 1"

# ---------------------------------------------------------------------------- #
#                                  setup path                                  #
# ---------------------------------------------------------------------------- #

export PATH="$PATH:/opt/nvim-linux64/bin"
export EDITOR=nvim
export VISUAL=nvim

# if type fastfetch >/dev/null; then
#     fastfetch
# fi
