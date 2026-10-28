# README

## Install (Debian/Ubuntu x86-64)

If curl or HTTPS certificates are missing, bootstrap them first:

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates
```

Omit `sudo` when running as root. Otherwise, run directly:

```bash
curl -fsSL https://raw.githubusercontent.com/Chr1sC0de/dotfiles/refs/heads/master/install.sh | bash - \
    && . "$HOME/.bashrc" \
    && nvim --headless "+Lazy! sync" +MasonToolsInstallSync +q!
```

The installer downloads jq, bat, ripgrep, and fd concurrently from official
GitHub releases. Optional GitHub CLI (`bash utils/dependencies-install-all.sh --github`)
also uses a release binary. System packages are installed through APT only when
missing; an already-provisioned system skips APT entirely for default dependencies.
Non-root installation requires sudo access.

To use Debian packages for jq, bat, ripgrep, and fd instead:

```bash
DOTFILES_CORE_SOURCE=apt bash utils/dependencies-install-all.sh
```

See [installation audit](docs/install-audit.md) for container tests and measurements.

If tar reports ownership/permission issues, this may help:

```bash
export TAR_OPTIONS="--no-same-owner --no-same-permissions"
```

In Docker images during build:

```dockerfile
ENV TAR_OPTIONS="--no-same-owner --no-same-permissions"
ENV DOTFILES_INSTALL_SCRIPT=https://raw.githubusercontent.com/Chr1sC0de/dotfiles/refs/heads/master/install.sh

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -fsSL "$DOTFILES_INSTALL_SCRIPT" | bash -

RUN bash -l -i -c '. "$HOME/.bashrc" && nvim --headless "+Lazy! sync" +MasonToolsInstallSync +q!'
```

Default dotfile installation (`bash utils/dotfiles-install.sh` from this repository)
includes Herdr configuration, search roots in `~/.config/herdr-sessionizer/config.toml`,
and the `herdr-sessionizer` and `herdr-sessionizer-preview` commands in `~/.local/bin`.
Existing installations can add the search config with
`bash utils/symlink-create.sh config/herdr-sessionizer/config.toml`.
The picker requires uv, which selects or downloads Python for TOML parsing.
Install Herdr separately. `Ctrl+Q, D` can merge the current linked worktree into
the primary checkout, then remove its checkout and local branch; Squash is the default.
See [picker setup and usage](my-profile/scripts/herdr-sessionizer/README.md).
