#! /bin/bash

: '
Source this from the .bashrc file not the .profile file
as it will cause an error
'

# shellcheck disable=SC1091
source "$HOME/.my-profile/variables.sh"
source "$PROFILE_FOLDER/utils/__init__.sh"
source "$PROFILE_FOLDER/private-variables/__init__.sh"

source "$PROFILE_FOLDER/rye.sh"
source "$PROFILE_FOLDER/nvm.sh"
source "$PROFILE_FOLDER/aws.sh"
source "$PROFILE_FOLDER/nvim.sh"
source "$PROFILE_FOLDER/starship.sh"
source "$PROFILE_FOLDER/fzf.sh"

# disable ctrl+s in terminal
stty -ixon

# ---------------------------------------------------------------------------- #
#                                  setup alias                                 #
# ---------------------------------------------------------------------------- #

alias clip="xclip -selection c"

# ---------------------------------------------------------------------------- #
#                                  setup path                                  #
# ---------------------------------------------------------------------------- #

export PATH="$PATH:/opt/nvim-linux64/bin"
export EDITOR=nvim
export VISUAL=nvim

# if type fastfetch >/dev/null; then
#     fastfetch
# fi
