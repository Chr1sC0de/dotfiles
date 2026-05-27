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
