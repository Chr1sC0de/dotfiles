# Herdr shell pickers

`Ctrl+Q, K` opens projects; `Ctrl+Q, F` opens repositories and worktrees.
Both use native 150 × 45 Herdr popups. Enter opens or focuses a workspace.
Escape and Ctrl+C cancel. Ctrl+R refreshes the preview. In the worktree menu,
Ctrl+N (or the New branch row) prompts for a branch name based on HEAD.

`Ctrl+Q, D` deletes the current workspace's linked worktree. The popup shows the
workspace, full checkout path, and branch, with Cancel selected initially.
Choose checkout only or checkout and local branch. The workspace and its panes
close after checkout removal and branch handling finish, so the popup stays alive
for branch deletion and its confirmations. Before closing, the picker returns to
this repository's primary checkout workspace, opening one at that root if needed.
It matches checkout paths rather than workspace labels, so other open projects
cannot become the return destination. If returning to the root fails, the removed
worktree's workspace stays open with an error. Primary checkouts cannot be removed;
detached checkouts offer checkout only.
If modified or untracked files prevent removal, type the full checkout path to
confirm forced removal. If the local branch is unmerged, type its exact name to
confirm forced branch deletion. These are separate confirmations. Escape and
Ctrl+C cancel, and a cancelled branch deletion leaves the already-removed checkout
removed. Branch errors and retention messages remain visible until acknowledged
before the workspace closes. Checkout removal failures leave the workspace open.
Remote branches are unaffected. After changing bindings, run
`herdr server reload-config` to activate them.

To check out an existing remote branch, run `git fetch origin`, then use
`Ctrl+Q, F`, choose the repository, and select `[remote] origin/branch-name`.
This creates a local branch and checkout from that remote ref. If the local branch
already exists, choose its `[local]` row instead.

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
`herdr-sessionizer remove-current` requires the active workspace context supplied
by a Herdr popup and skips discovery, search configuration, and uv.
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
bash tests/herdr_worktree_remove_spec.sh
shellcheck -x -P my-profile/scripts/herdr-sessionizer my-profile/scripts/herdr-sessionizer/*.sh tests/herdr_sessionizer_spec.sh tests/herdr_worktree_remove_spec.sh
```

Tests use fake Herdr/fzf commands, temporary Git repositories, and a controlling
terminal for branch prompts. Removal tests also simulate the popup receiving
SIGHUP when its workspace closes and check that branch handling and temporary-file
cleanup and selection of the correct project root have already finished. Tests
cover reusing the root workspace, opening a missing root, duplicate labels, and
return failures. Project and worktree opening were also checked
in a separate named Herdr session.
