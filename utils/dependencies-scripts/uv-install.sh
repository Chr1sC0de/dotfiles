#!/usr/bin/env bash

curl -LsSf https://astral.sh/uv/install.sh | bash

# since uv is now installed, install all the othe scripts
#
"$HOME"/.local/bin/uv tool install prek
"$HOME"/.local/bin/uv tool install commitizen
"$HOME"/.local/bin/uv tool install toml2json
"$HOME"/.local/bin/uv tool install neovim-remote
