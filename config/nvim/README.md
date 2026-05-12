# README

## Workmux Keybindings

This config adds guided [workmux](https://workmux.raine.dev/) bindings under `<leader>w`.
The leader key is space.

| Key | Action |
| --- | --- |
| `<leader>wa` | Prompt for a task and run `workmux add -A -p <prompt>` |
| `<leader>wA` | Prompt for a branch/name and run `workmux add <name>` |
| `<leader>wo` | Pick a worktree from `workmux list --json` and open it |
| `<leader>wO` | Pick a worktree and open it with `--continue` |
| `<leader>ww` | Open the dashboard on the worktrees tab |
| `<leader>wd` | Open the dashboard |
| `<leader>wD` | Open the dashboard diff view |
| `<leader>ws` | Toggle the Workmux sidebar |
| `<leader>wn` | Jump to the next sidebar agent |
| `<leader>wp` | Jump to the previous sidebar agent |
| `<leader>wL` | Jump to the most recently done or waiting agent |
| `<leader>wc` | Pick a worktree and close its window |
| `<leader>wm` | Pick a worktree and merge its branch after exact-name confirmation |
| `<leader>wr` | Pick a worktree and remove it after exact-name confirmation |

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
