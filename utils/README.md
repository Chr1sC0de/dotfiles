# README

to install, tar options are required when installing under root in docker, if not running in docker as root no need

```bash
export TAR_OPTIONS="--no-same-owner --no-same-permissions"
apt-get update -y \
    && apt-get install curl -y \
    && curl https://raw.githubusercontent.com/Chr1sC0de/dotfiles/refs/heads/master/install.sh | bash - \
    && . $HOME/.bashrc \
    && TAR_OPTIONS="--no-same-owner --no-same-permissions" nvim --headless "+Lazy! sync" +MasonToolsInstallSync +qa!
```
