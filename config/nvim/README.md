# README

## Worktree Keybindings

This config adds a multiplexer-aware worktree workflow under `<leader>w`. The
leader key is space. Inside Herdr, commands use Herdr-native workspaces,
worktrees, panes, and agents. Inside tmux, the same commands retain their
existing [Workmux](https://workmux.raine.dev/) behavior. Herdr takes precedence
if both `HERDR_ENV` and `TMUX` are present.

| Key | Action |
| --- | --- |
| `<leader>wa` | Prompt for a contextual task. Herdr generates a branch, starts a single-pane Codex workspace in the background, submits the task, and notifies when it has started; Workmux runs `add -A -p`. Visual mode includes the selection. |
| `<leader>wA` | Prompt for an explicit branch, create its worktree, and open Neovim in the root pane without starting Codex. |
| `<leader>wo` | Pick and open a worktree with a fresh agent when a new workspace is required. |
| `<leader>wO` | Pick and open a worktree, using `codex resume --last` when Herdr must recreate its workspace. |
| `<leader>ww` | Browse worktrees (the Workmux worktree dashboard in tmux). |
| `<leader>wd` | Browse Herdr workspaces or open the Workmux dashboard. |
| `<leader>wD` | Open Workmux dashboard diff; Herdr reports that no native equivalent exists. |
| `<leader>ws` | Toggle the Workmux sidebar; in Herdr use its native `prefix+b` sidebar. |
| `<leader>wn` | Focus the next agent, wrapping at the end. |
| `<leader>wp` | Focus the previous agent, wrapping at the beginning. |
| `<leader>wL` | Focus the latest done/blocked Herdr agent or Workmux's last done agent. |
| `<leader>wc` | Close an open non-main workspace while preserving its worktree. |
| `<leader>wm` | Merge through Workmux; Herdr reports that merging remains an explicit Git operation. |
| `<leader>wr` | Exactly confirm and remove a selected non-main worktree. |

Use `:WorktreePromptContextToggle` to switch `<leader>wa` and
`:WorktreeAddPrompt` between context-aware prompts and plain prompt text for the
current Neovim session. Context-aware mode is enabled by default. The old
`:WorkmuxPromptContextToggle` and `:WorkmuxAddPrompt` names remain aliases.

The implementation lives in `lua/workmux/`, is exposed through
`lua/config/workmux.lua`, and registers its own keymaps from
`lua/workmux/commands.lua`. Workmux TUI commands use `FTerm` when available and
fall back to a Neovim terminal tab. Herdr orchestration uses its structured CLI
responses directly and leaves the Sessionizer plugin independent.

## Codex Integration

This config includes a local Codex chat bridge under `lua/codex/` and a hook
receiver at `bin/codex-nvim-hook`.

Commits use an explicit two-step workflow. Run `:CodexPrepareCommit` to stage
all current changes and generate a Conventional Commit message in the
background. When the ready notification appears, run `:CodexCommit` to commit
that exact staged snapshot. Work added after preparation may remain unstaged;
changing the staged snapshot requires preparing again.

Run `:CodexReviewCommit` before committing to open an optional review popup.
Press `a` or `<Enter>` to accept and commit, `e` to edit the subject, `f` to
send feedback to Codex and request another proposal, or `r` to reject the
prepared message while preserving staged changes. Press `q` or `<Esc>` to close
the popup without discarding the prepared message. `:CodexCommit` remains
available when no review is needed.

When Neovim runs inside Herdr, each new chat starts as a real Codex agent in a
right-hand split of Neovim's current tab. The split remains visible until the
shell and agent are ready; Neovim then regains focus and its pane is zoomed.
Lifecycle notifications report startup, readiness, and failure. The Neovim
chat buffer displays the terminal through `herdr agent attach` and includes a
virtual keybinding header, so the attached buffer remains the primary chat UI
while Herdr retains native agent detection. Outside Herdr, chats continue to
launch directly in Neovim terminals.

Ephemeral commands and edits always run as independent background `codex exec`
processes managed by Neovim. They can run in parallel without creating Herdr
workspaces, tabs, or splits. Neovim retains its spinner, diagnostics, lifecycle
notifications, jobs panel, cancellation controls, and session-only Markdown
scratch result.
Open a completed result from `:CodexJobs`; it appears in the current window
without creating a result file. Press `f` from either the result or its jobs
panel row to continue the native Codex thread, `s` to return to its source, or
`q` to close the result. Codex persists the underlying thread so follow-ups use
its native conversation history, but Neovim does not restore result buffers or
jobs after restarting. If Neovim is not running inside Herdr, jobs fall back to
direct `codex exec` processes with the same result and follow-up behavior.

Use `:CodexChatAttach` or `<leader>aA` to reconnect to a surviving agent across
the current Herdr session. The chat-buffer panel also provides `a` for this
picker. Explicitly deleting a chat closes its backing Herdr pane; hiding its
buffer or exiting Neovim leaves the agent running. When Codex itself exits for
any reason, its dedicated Herdr pane closes automatically and an attached
Neovim chat buffer is removed. This cleanup is owned by the Herdr pane, so it
still runs while Neovim is detached or closed.

The dotfiles installer symlinks `config/nvim` by default, so the Neovim-side
hook script is installed automatically on a new machine:

```text
$HOME/.config/nvim/bin/codex-nvim-hook
```

Codex itself still needs a one-time hook registration in `~/.codex/hooks.json`.
That file is local Codex state and is not managed by this repo. Add the Neovim
hook to the lifecycle events Codex should report back into the running Neovim
session:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "command": "$HOME/.config/nvim/bin/codex-nvim-hook",
            "type": "command"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "command": "$HOME/.config/nvim/bin/codex-nvim-hook",
            "type": "command"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "command": "$HOME/.config/nvim/bin/codex-nvim-hook",
            "type": "command"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "command": "$HOME/.config/nvim/bin/codex-nvim-hook",
            "type": "command"
          }
        ]
      }
    ]
  }
}
```

If `~/.codex/hooks.json` already contains hooks, keep those entries and append
the `codex-nvim-hook` entry to each matching event. Use
`$HOME/.config/nvim/bin/codex-mux-status-hook <status>` for lifecycle status
hooks, where status is `working`, `waiting`, `done`, or `clear`. The dispatcher
lets Herdr own its detected agent state, delegates to Workmux inside tmux, and
safely does nothing outside either multiplexer.

After changing hooks, start a new Codex chat and run `:CodexHealth` in Neovim.
The chat buffer panel should show IPC as `READY` when the hook server is
available, then `SEEN` after Codex emits a lifecycle event.

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
