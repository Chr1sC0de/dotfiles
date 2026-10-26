# Herdr shell pickers

`Ctrl+Q, K` opens projects; `Ctrl+Q, F` opens repositories and worktrees.
Both use native 150 × 45 Herdr popups. Enter opens or focuses a workspace.
Escape and Ctrl+C cancel. Ctrl+R refreshes the preview. In the worktree menu,
Ctrl+N (or the New branch row) prompts for a branch name based on HEAD.

`Ctrl+Q, D` offers deletion or **Merge, then delete checkout and local branch**
for the current linked worktree. Cancel is initially selected. The popup shows
source and destination branches, both checkout paths, and the workspace closure
notice. The destination is the branch currently checked out in the primary checkout.

Merge choices are Squash (preselected), Normal (fast-forward when possible),
Merge commit (`--no-ff`), and Fast-forward only. Explicit flags override Git merge
mode defaults. Squash offers an editable default message, Generate with OpenCode,
and Cancel. OpenCode drafts a Conventional Commit subject from the committed changes;
you can edit it before Enter starts the merge. Escape or Ctrl+C cancels selection,
generation, or message editing. OpenCode is optional and uses an independent
`run --standalone --format json` invocation with tool use denied, retaining
configured authentication and model. Inherited Neovim routing variables and inline
plugin/MCP configuration are removed. JSON text events supply the draft; generation
errors, empty output, or invalid subjects return to the message chooser.

Merging requires clean, attached source and destination branches with no unfinished
Git operation. Branches, commits, workspace membership, and worktree registration
are rechecked after prompts and before cleanup. A locked source is rejected.
Conflicts or commit-hook failures preserve Git's resulting state and the source
checkout, branch, and workspace. After acknowledgement, the primary workspace is
focused or opened for manual resolution. Empty squash results retain the source;
already incorporated ancestors can be cleaned up without another commit.

Successful merges remove the checkout without forcing, then delete the unchanged
local branch after verifying incorporation. A squash requires a verified successful
commit. Cleanup errors keep the merge and remaining source state, with an error
showing the completed steps. The source workspace closes only after branch handling
and temporary-file cleanup. Return targets match checkout paths, not labels.

Both deletion-only options remain available. Dirty checkout deletion requires typing
the full checkout path; unmerged local branch deletion separately requires its exact
name. Cancelling branch deletion leaves the already-removed checkout removed.
Primary checkouts cannot be removed; detached checkouts offer checkout only.
All operations are local: no fetch, push, remote deletion, or automatic commit of
dirty work. After changing bindings, run `herdr server reload-config`.

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
uses `uv run` with a uv-managed Python 3.11+ for the built-in TOML parser;
no manual Python installation or version check is needed. The first run may
download a compatible managed interpreter, which uv reuses on subsequent runs.
The parser runs from `/` in an isolated environment, ignores inherited Python
and uv interpreter/project settings, and excludes local modules and user site
packages from imports. This allows invocation from a Podman-mounted checkout
whose `.venv` cannot run on the host. Only the parser receives this cleanup;
Herdr commands and the project shells they open retain the caller's environment.
If uv cannot obtain a managed runtime, its error is shown and the picker stops
before querying Herdr or opening fzf.
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
bash tests/herdr_worktree_merge_spec.sh
shellcheck -x -P my-profile/scripts/herdr-sessionizer my-profile/scripts/herdr-sessionizer/*.sh tests/herdr_sessionizer_spec.sh tests/herdr_worktree_remove_spec.sh tests/herdr_worktree_merge_spec.sh
```

Tests use fake Herdr/fzf commands, temporary Git repositories, and a controlling
terminal for branch prompts. Parser tests include a failing mounted `.venv`,
shadowed standard-library modules, and inherited Python/uv settings. The tests
reuse uv's managed interpreter directory while replacing HOME for fixtures.
Removal tests also simulate the popup receiving
SIGHUP when its workspace closes and check that branch handling and temporary-file
cleanup and selection of the correct project root have already finished. Tests
cover reusing the root workspace, opening a missing root, duplicate labels, and
return failures. Project and worktree opening were also checked
in a separate named Herdr session.
