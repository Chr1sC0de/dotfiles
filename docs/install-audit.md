# Debian/Ubuntu installation audit

## Current installation strategy

The target server is Debian/Ubuntu x86-64 with slow APT access. Official binaries
are therefore the default for jq, bat, ripgrep, and fd, downloaded concurrently.
GitHub CLI also uses an official release archive, without adding an APT repository.
Eza, lazygit, and Neovim use curl; wget is no longer required. Neovim downloads
only one archive per installation, including for non-root users.

`utils/apt-install-missing.sh` checks package status locally with `dpkg-query`.
If all requested system packages are installed, it performs no APT operations.
Otherwise it refreshes indexes and installs only missing packages. Bootstrap
shares its index-refresh status with core setup so they do not refresh twice.
Sudo is a prerequisite for non-root users rather than a package they must install
using sudo. Existing fzf/TPM checkouts are reused, and no automatic autoremove runs.
The optional Ghostty installer uses the same helper for its prerequisites.

Use `DOTFILES_CORE_SOURCE=apt` to select distribution packages for the four core
CLI tools. Other direct-download tools keep their existing installation method.

## Reproduce

```bash
# Default dependencies plus gh, configuration, and a repeat pass
bash tests/install_debian_audit.sh
AUDIT_USER=user bash tests/install_debian_audit.sh

# Core dependencies plus gh only
AUDIT_SCOPE=core bash tests/install_debian_audit.sh
AUDIT_IMAGE=docker.io/library/ubuntu:24.04 AUDIT_USER=user AUDIT_SCOPE=core \
    bash tests/install_debian_audit.sh

# Compare core installation sources
for user in root user; do
    for source in apt binaries; do
        AUDIT_USER="$user" DOTFILES_CORE_SOURCE="$source" AUDIT_SCOPE=core \
            bash tests/install_debian_audit.sh
    done
done
```

Options:

- `CONTAINER_ENGINE`: `podman` (default) or `docker`.
- `AUDIT_IMAGE`: `docker.io/library/debian:13-slim` by default; use a digest for repeatable comparisons.
- `AUDIT_USER`: `root` or `user` (an unprivileged account with passwordless sudo inside the container).
- `DOTFILES_CORE_SOURCE`: `binaries` (default) or `apt`.
- `AUDIT_SCOPE`: `full` (default) or `core`.
- `AUDIT_RESULTS`: defaults to a timestamped directory under `/tmp/opencode/install-audit`.

Each invocation uses a fresh container and copies the local checkout into it.
It records stage timings, exit codes, logs, installed Debian packages, image
metadata, and the tracked working-tree diff. The container is removed afterward.
The second pass replaces APT with a failing stub: any attempted APT operation
fails the repeat-install test. Bootstrap and image-pull time should be considered
separately from dependency installation.

Smoke checks run as the installation user and exercise jq, bat, ripgrep, fd,
and a tmux server, and check command versions including gh. Full mode additionally
runs other default dependency scripts and configuration linking. The harness does
not clone the remote dotfiles repository or run Neovim plugin/Mason initialization.
Ghostty and Homebrew are outside its scope.

## Binary-default validation

The following fresh-container runs passed first installs, repeat installs with APT
blocked, and functional smoke checks. Logs are under `/tmp/opencode/install-audit`:

| Image | User / scope | Result directory |
| --- | --- | --- |
| Debian 13 | root / full | `20261028-145728-root-binaries-full` |
| Debian 13 | root / core | `20261028-145942-root-binaries-core` |
| Debian 13 | non-root / full | `20261028-150258-user-binaries-full` |
| Ubuntu 24.04 | non-root / core | `20261028-150026-user-binaries-core` |
| Debian 13 | root / APT fallback core | `20261028-150135-root-apt-core` |

Repeat core stages measured 0 seconds at the harness's one-second resolution.
Binary-mode package inventories contain none of jq, bat, ripgrep, fd-find, wget,
or gh as Debian packages. GitHub CLI 2.103.3 and its pinned archive checksum were
validated in the final core and non-root full runs. Bash syntax, ShellCheck, and
Git whitespace checks passed. The work server itself has not been benchmarked.

## Historical measurements (Debian 13, x86-64, October 28, 2026)

Before the binary-default/missing-package changes, the initial default run measured:

| Stage | Seconds |
| --- | ---: |
| APT index refresh | 2 |
| Bootstrap packages | 9 |
| Core dependencies | 21 |
| Rust | 15 |
| grip-grab | 27 |

`cargo-binstall` compiled `grip-grab 0.6.7` from source, with about 24 seconds of
compilation. The native toolchain is a real dependency for this resolved install.

After fixing existing-checkout failures, but before skipping already-installed APT packages:

| Installation user | Source | First core pass | Repeat core pass | Status |
| --- | --- | ---: | ---: | --- |
| root | APT | 29 s | 1 s | Passed |
| root | binaries | 27 s | 1 s | Passed |
| non-root | APT | 29 s | 1 s | Passed |
| non-root | binaries | 31 s | 1 s | Passed |

The full non-root binary-mode run also passed (`20261028-135119-user-binaries-full`).
These local measurements showed no consistent binary-download speedup. The default
changed to binaries to accommodate the work server's slow APT access, not because
these local measurements prove it faster everywhere. Work-server timing remains
unmeasured.

## Dependency decisions

| Dependency | Decision / evidence |
| --- | --- |
| jq, bat, ripgrep, fd | Official pinned releases by default; matching installed versions are skipped. |
| build-essential | Retain: observed source compilation of grip-grab needs a linker/toolchain. |
| CMake | Retain for configured editor CMake workflows. |
| Python 3 | Retain: uv environments do not replace every consumer of system python3. |
| Git, curl, certificates | Bootstrap/system prerequisites; skip when installed. |
| tmux | Keep APT, tested by starting and stopping a server. |
| wget | Removed from bootstrap/core requirements; downloads use curl. |
| sudo | Non-root prerequisite, provisioned by the test harness. |
| gh | Official GitHub release archive in ~/.local/bin; included in audit runs. |

The core release versions are jq 1.7.1, bat 0.25.0, fd 10.2.0, and ripgrep 14.1.1.
They match upstream versions in the tested Debian 13 packages, though distribution
patches differ. x86-64 and ARM64 assets are mapped for these tools and gh; the wider
installer targets x86-64 and ARM64 was not tested. Full editor provisioning,
package-removal experiments, and checksum pinning for the four core release tools
remain outside this audit.
