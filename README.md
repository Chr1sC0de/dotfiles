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
ENV DOTFILES_INSTALL_SCRIPT=https://raw.githubusercontent.com/Chr1sC0de/dotfiles/refs/heads/master/install.sh;

RUN apt-get update -y \
    && apt-get install curl -y \
    && curl $DOTFILES_INSTALL_SCRIPT | bash -;

RUN bash -l -i -c "\. $HOME/.bashrc && nvim --headless '+Lazy! sync\' +MasonToolsInstallSync +q!";
```

Default dotfile installation (`bash utils/dotfiles-install.sh` from this repository)
includes Herdr configuration, search roots in `~/.config/herdr-sessionizer/config.toml`,
and the `herdr-sessionizer` and `herdr-sessionizer-preview` commands in `~/.local/bin`.
Existing installations can add the search config with
`bash utils/symlink-create.sh config/herdr-sessionizer/config.toml`.
The picker requires uv, which selects or downloads Python for TOML parsing.
Install Herdr separately.
See [picker setup and usage](my-profile/scripts/herdr-sessionizer/README.md).
