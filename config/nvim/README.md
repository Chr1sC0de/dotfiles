# README

## Workmux Keybindings

This config adds guided [workmux](https://workmux.raine.dev/) bindings under `<leader>w`.
The leader key is space.

| Key | Action |
| --- | --- |
| `<leader>wa` | Prompt for a task, then run `workmux add -A -p <prompt>` with current-file context by default; in visual mode, include the selected lines as context. |
| `<leader>wA` | Prompt for a branch or worktree name, then run `workmux add <name>` to create a new worktree for that name. |
| `<leader>wo` | Load choices from `workmux list --json`, pick one, then run `workmux open <handle>` to open that worktree. |
| `<leader>wO` | Pick a worktree and run `workmux open <handle> --continue`; `--continue` reopens the agent session while opening it. |
| `<leader>ww` | Run `workmux dashboard --tab worktrees` in a terminal so the dashboard starts on the worktrees tab. |
| `<leader>wd` | Run `workmux dashboard` in a terminal to open the default interactive dashboard. |
| `<leader>wD` | Run `workmux dashboard --diff` in a terminal to open the dashboard diff view. |
| `<leader>ws` | Run `workmux sidebar`; with no subcommand this toggles the Workmux sidebar. |
| `<leader>wn` | Run `workmux sidebar next` to move focus to the next agent shown in the sidebar. |
| `<leader>wp` | Run `workmux sidebar prev` to move focus to the previous agent shown in the sidebar. |
| `<leader>wL` | Run `workmux last-done` to jump to the most recently done or waiting agent. |
| `<leader>wc` | Pick a non-main worktree, then run `workmux close <handle>` to close its Workmux window without removing the worktree. |
| `<leader>wm` | Pick a non-main worktree, type its exact handle to confirm, then run `workmux merge <branch>` in a terminal. |
| `<leader>wr` | Pick a non-main worktree, type its exact handle to confirm, then run `workmux remove <handle>` in a terminal. |

Use `:WorkmuxPromptContextToggle` to switch `<leader>wa` and
`:WorkmuxAddPrompt` between context-aware prompts and plain prompt text for the
current Neovim session. Context-aware mode is enabled by default.

The implementation lives in `lua/workmux/`, is exposed through
`lua/config/workmux.lua`, and registers its own keymaps from
`lua/workmux/commands.lua`. Interactive TUI commands use `FTerm` when
available and fall back to a Neovim terminal tab.

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

When Neovim runs inside Herdr, it creates one persistent, unfocused `Codex`
workspace with a `home` tab. Each new chat is launched as a real Codex agent in
its own tab there, leaving the project workspace uncluttered. The Neovim chat
buffer displays that terminal through `herdr agent attach`, so Herdr retains
native agent detection and the agent survives an editor restart. If the Codex
workspace is closed manually, the next launch recreates it. Outside Herdr,
chats continue to launch directly in Neovim terminals.

Ephemeral commands and edits share that Codex workspace and run in their own
unfocused tabs. Their labels include the action, job number, target file, and
instruction, for example `edit #12 · jobs.lua · fix cancellation`. The tabs
close themselves when the one-shot job finishes, while the persistent `home`
tab keeps the workspace available and Neovim retains its spinner, diagnostics,
jobs panel, cancellation controls, and Markdown result. If Neovim is not
running inside Herdr, ephemeral jobs fall back to direct `codex exec` processes.

Use `:CodexChatAttach` or `<leader>aA` to reconnect to a surviving agent across
the current Herdr session. The chat-buffer panel also provides `a` for this
picker. Explicitly deleting a chat closes its backing Herdr tab; hiding its
buffer or exiting Neovim leaves the agent running. When Codex itself exits for
any reason, its dedicated Herdr tab closes automatically and an attached
Neovim chat buffer is removed. This cleanup is owned by the Herdr tab, so it
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
the `codex-nvim-hook` entry to each matching event. For example, the existing
`workmux set-window-status ...` hooks can coexist with the Neovim hook.

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
