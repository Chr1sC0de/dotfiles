vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local attachment = require("agents.attachment")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/config/nvim/.git", "p")
vim.fn.mkdir(root .. "/config/nvim/lua", "p")
local function git(args)
	local result = vim.system(args, { text = true }):wait()
	assert(result.code == 0, result.stderr)
end
git({ "git", "init", "-q", root })
vim.cmd.cd(root)
local expected = vim.uv.fs_realpath(root)
assert(attachment.project() == expected)
vim.api.nvim_buf_set_name(0, root .. "/config/nvim/lua/test.lua")
assert(attachment.project() == expected, "empty nested .git directory must not change the project")

-- A real nested repository is still a distinct project.
vim.fn.mkdir(root .. "/nested", "p")
git({ "git", "init", "-q", root .. "/nested" })
vim.api.nvim_buf_set_name(0, root .. "/nested/test.lua")
assert(attachment.project() == expected .. "/nested")

-- Worktree .git files must resolve through Git too.
local worktree = root .. "-worktree"
git({
	"git",
	"-C",
	root,
	"-c",
	"user.name=Test",
	"-c",
	"user.email=test@example.invalid",
	"commit",
	"--allow-empty",
	"-qm",
	"initial",
})
git({ "git", "-C", root, "worktree", "add", "-qb", "test", worktree })
vim.api.nvim_buf_set_name(0, worktree .. "/test.lua")
assert(attachment.project() == vim.uv.fs_realpath(worktree))
vim.cmd.cd("/")
vim.fn.delete(worktree, "rf")
vim.fn.delete(root, "rf")
print("agents_project_test: OK")
