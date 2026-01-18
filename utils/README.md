# README

if we have tar issues, this may help

```bash
export TAR_OPTIONS="--no-same-owner --no-same-permissions"
```

```bash
sudo apt-get update -y \
    && sudo apt-get install curl -y \
    && curl https://raw.githubusercontent.com/Chr1sC0de/dotfiles/refs/heads/master/install.sh | bash - \
    && . $HOME/.bashrc \
    && nvim --headless "+Lazy! sync" +MasonToolsInstallSync +q!
```

when running as root, sometimes it's better to not use sudo

```bash
apt-get update -y \
    && apt-get install curl -y \
    && curl https://raw.githubusercontent.com/Chr1sC0de/dotfiles/refs/heads/master/install.sh | bash - \
    && . $HOME/.bashrc \
    && nvim --headless "+Lazy! sync" +MasonToolsInstallSync +q!
```

in docker images during build

```dockerfile
ENV TAR_OPTIONS="--no-same-owner --no-same-permissions"
ENV DOTFILES_INSTALL_SCRIPT=https://raw.githubusercontent.com/Chr1sC0de/dotfiles/refs/heads/master/install.sh

RUN apt-get update -y \
    && apt-get install curl -y \
    && curl $DOTFILES_INSTALL_SCRIPT  | bash -

RUN /bin/bash -lc '. ~/.bashrc && nvim --headless \"+Lazy! sync\" +MasonToolsInstallSync +q!'
```
