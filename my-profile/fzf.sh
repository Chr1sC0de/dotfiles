#!/usr/bin/env bash

if [[ "$(type fzf &>/dev/null)" ]]; then

    if type fd &>/dev/null; then
        export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
        export FZF_CTRL_T_COMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

        _fzf_compgen_path() {
            fd --hidden --exclude .git . "$1"
        }

        _fzf_compgen_dir() {
            fd --type=d --hidden --exclude .git . "$1"
        }

    else
        echoinfo "fd not installed, shortcuts excluded"
    fi

    . "$PROFILE_FOLDER/fzf-git.sh"
fi
