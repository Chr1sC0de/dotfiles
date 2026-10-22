# Herdr shell pickers

`Ctrl+Q, K` opens projects; `Ctrl+Q, F` opens repositories and worktrees.
Both use native 150 × 45 Herdr popups. Enter opens or focuses a workspace.
Escape and Ctrl+C cancel. Ctrl+R refreshes the preview. In the worktree menu,
Ctrl+N (or the New branch row) prompts for a branch name based on HEAD.

Rows show folder basenames for projects and checked-out worktrees, and workspace
names without appended IDs or paths. Workspace names that are absolute paths
also show only their basename. Type prefixes and full local/remote branch names
remain visible. Duplicate names stay as separate rows; use the preview's full
path and workspace ID to distinguish them. Workspace previews keep terminal
content and colors beneath these headers. Selection uses hidden row IDs, so
opening a row still targets its full path or workspace ID.

Edit `~/.config/herdr-sessionizer/config.toml` to change discovery. Installation
symlinks this file to `config/herdr-sessionizer/config.toml` in the dotfiles repo:

```toml
[[search_roots]]
path = "~/GitHub"
depth = 1

[[search_roots]]
path = "~/MyScratch"
depth = "recursive"
```

Each entry requires an absolute path (or a path starting with `~/`) and a
nonnegative integer depth or `"recursive"`. Depth 1 includes projects directly
inside a root; depth 0 includes only the root itself if it is a checkout.
`"recursive"` has no depth limit. Paths are read as data: shell variables and
commands are not evaluated. Missing roots are skipped.

Missing or empty configuration, or `search_roots = []`, disables discovery;
the projects picker still lists open workspaces. Malformed configuration reports
the file and error before opening the picker. The sibling `config.sh` is now
the TOML loader, not a place to configure roots.

Run `bash utils/dotfiles-install.sh` from the repository root. The default
installation includes both Herdr and sessionizer configuration, plus executable
symlinks `~/.local/bin/herdr-sessionizer` and
`~/.local/bin/herdr-sessionizer-preview`. Herdr itself must be installed separately.

For just the sessionizer commands and their search configuration:

```bash
bash utils/symlink-create.sh herdr-sessionizer
bash utils/symlink-create.sh herdr-sessionizer-preview
bash utils/symlink-create.sh config/herdr-sessionizer/config.toml
```

Existing installations need the third command to enable TOML-based discovery.
These targets also work with `utils/symlink-remove.sh`; removal preserves
unrelated files and links. Existing correct links are preserved. Conflicting
files and directories are reported; `--force` replaces only conflicting
symlinks. Link destinations are exact paths and never receive nested links.

The commands above leave Herdr's application configuration alone. To install
the popup keybindings too, separately run
`bash utils/symlink-create.sh config/herdr/config.toml`.
Use that exact file target; `config/herdr` is not an accepted target.

Run `herdr-sessionizer projects` or `herdr-sessionizer worktrees` directly.
Popup bindings invoke `herdr-sessionizer`, so `~/.local/bin` must be on Herdr's
PATH. The dotfiles profile adds it. The picker resolves its own symlink to load
the shared scripts and invokes the neighboring `preview.sh` directly.

Dependencies: Bash, Git, Herdr, fzf, jq, uv, and GNU coreutils for installation
(`ln -T`). The dotfiles dependency installer already installs uv. The picker
uses `uv run` to select Python 3.11+ for the built-in TOML parser; no manual
Python installation or version check is needed. The first run may download a
compatible interpreter, which uv reuses on subsequent runs. Parser execution
is isolated from the current project and its uv configuration. If uv cannot
obtain a runtime, its error is shown and the picker stops.
The picker includes `~/.local/bin` and `~/.fzf/bin` in PATH.
Optional bat/batcat renders README previews with color;
otherwise previews use cat or a directory listing.

Existing local branches are reused. Remote rows use the explicit remote ref as
the base; if that branch name already exists locally, the picker reports the
collision rather than substituting the local branch. Herdr controls checkout
locations and repository trust. New workspaces use the normal shell; no
Sessionizer layout or Bun runtime is involved. The installed plugin is retained
for rollback: restore the two `plugin_action` bindings in `config/herdr/config.toml`.

Validation from the dotfiles root:

```bash
bash tests/symlink_spec.sh
bash tests/herdr_sessionizer_spec.sh
shellcheck -x -P my-profile/scripts/herdr-sessionizer my-profile/scripts/herdr-sessionizer/*.sh tests/herdr_sessionizer_spec.sh
```

Tests use fake Herdr/fzf commands, temporary Git repositories, and a controlling
terminal for branch prompts. Live popup and worktree behavior was also checked
in a separate named Herdr session.
