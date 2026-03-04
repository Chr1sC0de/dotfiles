# README

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
