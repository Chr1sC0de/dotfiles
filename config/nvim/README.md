# README

## Worktree Keybindings

This config adds a multiplexer-aware worktree workflow under `<leader>w`. The
leader key is space. Inside Herdr, commands use Herdr-native workspaces,
worktrees, panes, and agents. Inside tmux, the same commands retain their
existing [Workmux](https://workmux.raine.dev/) behavior. Herdr takes precedence
if both `HERDR_ENV` and `TMUX` are present.

| Key | Action |
| --- | --- |
| `<leader>wa` | Prompt for a contextual task. Herdr generates a branch, starts a single-pane OpenCode workspace in the background, submits the task, and notifies when it has started; Workmux runs `add -A -p`. Visual mode includes the selection. |
| `<leader>wA` | Prompt for an explicit branch, create its worktree, and open Neovim in the root pane without starting OpenCode. |
| `<leader>wo` | Pick and open a worktree; Herdr also offers local/remote branches and opens Neovim when a workspace is required. |
| `<leader>wO` | Pick and open a worktree, using `opencode --continue` when Herdr must recreate its workspace. |
| `<leader>ww` | Browse worktrees and open Neovim in Herdr; open the Workmux worktree dashboard in tmux. |
| `<leader>wd` | Browse live Herdr agents with pane previews, or open the Workmux dashboard in tmux. |
| `<leader>wD` | Open Workmux dashboard diff; Herdr reports that no native equivalent exists. |
| `<leader>ws` | Toggle the Workmux sidebar; in Herdr use its native `prefix+b` sidebar. |
| `<leader>wn` | Focus the next agent, wrapping at the end. |
| `<leader>wp` | Focus the previous agent, wrapping at the beginning. |
| `<leader>wL` | Focus the latest done/blocked Herdr agent or Workmux's last done agent. |
| `<leader>wc` | Close an open non-main workspace while preserving its worktree. |
| `<leader>wm` | Merge through Workmux; Herdr reports that merging remains an explicit Git operation. |
| `<leader>wr` | Exactly confirm and remove a selected non-main worktree. |

In Herdr, `wo`, `wO`, and `ww` show existing worktrees followed by
`[local]` branches without checkouts and `[remote]` branches. The picker uses
cached Git refs immediately. Select **Fetch remotes / refresh** to fetch all
remotes and reload the list; available refs remain usable if fetching fails.

When a workspace must be created or reopened, `wo` and `ww` start `nvim .`
in the checkout. Use `wO` to resume OpenCode instead, or `wa` to submit an OpenCode
task. Existing workspaces are simply focused without starting another process.

Remote rows show matching local branches and whether their checkout is open.
Selecting one reuses a local branch whose upstream is that exact remote ref,
including differently named branches. A unique match opens directly; multiple
matches offer a local-branch chooser. This applies equally to `main`, `master`,
and feature branches. A same-name local branch at the identical commit with no
upstream gains the selected upstream and is reused.

Opening an existing local branch reports whether it is equal, ahead, behind, or
diverged from the selected remote, with commit counts. Local commits and working
files remain unchanged, including in dirty or behind checkouts. Existing
upstreams are preserved. If a same-name branch has a different upstream, or has
different commits and no upstream, choose to open it unchanged or supply another
local name.

When no matching local branch exists, selecting `[remote] origin/feature/foo`
creates local `feature/foo` at that remote commit and explicitly sets its
upstream to `origin/feature/foo`. If checkout creation fails after the tracking
branch was created, retry using its `[local]` row. Opening an existing workspace
focuses it without starting another process. Tmux/Workmux retains its existing
picker behavior.

Use `:WorktreePromptContextToggle` to switch `<leader>wa` and
`:WorktreeAddPrompt` between context-aware prompts and plain prompt text for the
current Neovim session. Context-aware mode is enabled by default. The old
`:WorkmuxPromptContextToggle` and `:WorkmuxAddPrompt` names remain aliases.

The implementation lives in `lua/workmux/`, is exposed through
`lua/config/workmux.lua`, and registers its own keymaps from
`lua/workmux/commands.lua`. Workmux TUI commands use `FTerm` when available and
fall back to a Neovim terminal tab. Herdr orchestration uses its structured CLI
responses directly and leaves the Sessionizer plugin independent.

## OpenCode Integration

This config includes a local OpenCode chat bridge under `lua/opencode/` and a hook
receiver at `bin/opencode-nvim-hook`.

Run `:OpenCodeCommit` to stage all saved changes, generate a Conventional Commit
message, and commit automatically in the background with normal Git hooks.
You can keep editing: unsaved buffers are left alone, and edits saved after
staging remain unstaged for your next commit. Progress and completion appear
as notifications without opening a popup or taking focus.

For the manual workflow, run `:OpenCodePrepareCommit` to stage changes and prepare
a message without committing. If a prepared message exists, `:OpenCodeCommit`
uses that message and staged snapshot without restaging or regenerating.
Changing the staged snapshot aborts the operation and discards the prepared
message; it never automatically restages within that invocation. If a commit
fails and its staged snapshot still matches, the message is retained so
`:OpenCodeCommit` can retry. Otherwise, prepare again or run `:OpenCodeCommit` afresh.

Run `:OpenCodeReviewCommit` before committing to open an optional review popup.
Press `a` or `<Enter>` to accept and commit, `e` to edit the subject, `f` to
send feedback to OpenCode and request another proposal, or `r` to reject the
prepared message while preserving staged changes. Press `q` or `<Esc>` to close
the popup without discarding the prepared message. `:OpenCodeCommit` remains
available when no review is needed.

When Neovim runs inside Herdr, each new chat starts as a real OpenCode agent in a
right-hand split of Neovim's current tab. The split remains visible until the
shell and agent are ready; Neovim then regains focus and its pane is zoomed.
Lifecycle notifications report startup, readiness, and failure. The Neovim
chat buffer displays the terminal through `herdr agent attach` and includes a
virtual keybinding header, so the attached buffer remains the primary chat UI
while Herdr retains native agent detection. Outside Herdr, chats continue to
launch directly in Neovim terminals.

Queries (read-only questions) and edits (file changes) always run as independent background `opencode run --standalone --format json`
processes managed by Neovim. They can run in parallel without creating Herdr
workspaces, tabs, or splits. Neovim retains its spinner, diagnostics, lifecycle
notifications, jobs panel, cancellation controls, and session-only Markdown
scratch result.
Open a completed result from `:OpenCodeJobs`; it appears in a dedicated tab without
creating a result file. Reopening a visible result focuses its existing tab
instead of creating a duplicate. Press `f` from either the result or its jobs
panel row to continue the native OpenCode thread, `s` to return to its source, or
`q` to close the result tab and return to the originating tab. OpenCode persists
the underlying thread so follow-ups use its native conversation history, but
Neovim does not restore result buffers or jobs after restarting. If Neovim is
not running inside Herdr, jobs fall back to direct `opencode run --standalone --format json` processes with
the same result and follow-up behavior.

Use `:OpenCodeQuery` to ask without editor context, `:OpenCodeQueryFile` for the
current file, and `:OpenCodeQuerySelection` for selected text. Diagnostic queries
use `:OpenCodeQueryFileDiagnostics`, `:OpenCodeQueryLineDiagnostics`, or
`:OpenCodeQuerySelectionDiagnostics`. Queries cannot modify files.
`:OpenCodeEditFile` and `:OpenCodeEditSelection` apply requested file changes.
The former `:OpenCodeCommand*` names have been replaced; existing keybindings
still work (`<leader>aq`, `<leader>ac`, `<leader>ar`, and `<leader>ae`).

Attaching an agent with `<leader>aA` remembers its identity for the current project
(each Git worktree is separate). `<leader>aa` returns to that attachment, including
after restarting Neovim, retaining the existing agent conversation and its model.
If the remembered agent is missing or has moved to a different pane/workspace,
the toggle offers reattachment rather than silently creating or selecting another chat.

Choose separate query, edit, and commit-message models with `<leader>am` or
`:OpenCodeEphemeralModel [query|edit|commit]`. Commit generation and message revisions use the saved commit model.
The picker queries OpenCode V2's model API through the authenticated CLI,
including `provider/model#variant` choices. Discovery times out after ten seconds.
On failure, the picker uses its last successful catalog, labeled **cached**.
Only model IDs and labels are cached, never provider credentials.
**CLI default**, **Custom…**, and the current selection remain available even
when discovery fails. An unlisted saved model is retained until you change it.

Selections are saved immediately in
`stdpath("state")/opencode/ephemeral-models.json` and restored across Neovim
restarts for all projects on this machine. Before selecting a model, jobs follow
the OpenCode CLI default; selecting **CLI default** restores that behavior.
A failed save leaves the selection active for the current session and displays
a warning. Existing thread follow-ups retain their original job's model;
starting a fresh edit from a result uses the saved edit preference.

Use `:OpenCodeChatAttach` or `<leader>aA` to reconnect to a surviving agent across
the current Herdr session. The chat-buffer panel also provides `a` for this
picker. Explicitly deleting a chat closes its backing Herdr pane; hiding its
buffer or exiting Neovim leaves the agent running. When OpenCode itself exits for
any reason, its dedicated Herdr pane closes automatically and an attached
Neovim chat buffer is removed. This cleanup is owned by the Herdr pane, so it
still runs while Neovim is detached or closed.

The dotfiles installer symlinks `config/nvim` by default, so the Neovim-side
hook script is installed automatically on a new machine:

```text
$HOME/.config/nvim/bin/opencode-nvim-hook
```

Managed launches automatically load `opencode-plugin/` through their private
OpenCode configuration. The plugin forwards prompt, completion, failure, and
input-request events to Neovim. No global hook registration is needed.

Run `:OpenCodeHealth` to check the CLI, Tandem, bridge, and Herdr integration.
The chat panel shows IPC as `READY`, then `SEEN` after a lifecycle event.

See [Tandem integration](../../docs/tandem-integration.md) for setup, the editing
contract, and reproducible checks.

## Subtree

To work with the current folder as a subtree

```bash
# add the remote
git remote add nvim-config git@github.com:Chr1sC0de/nvim-config.git

# to pull any changes to the main branch
git subtree pull --prefix=config/nvim nvim-config main --squash

# to push any changes to the main branch
git subtree push --prefix=config/nvim nvim-config main
```
