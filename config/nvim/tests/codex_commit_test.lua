vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")

local commit = require("codex.commit")
local state = require("codex.state")

local function expect_valid(message)
	local valid, reason = commit.validate_fallback(message)
	assert(valid, message .. " should be valid: " .. tostring(reason))
end

local function expect_invalid(message)
	local valid = commit.validate_fallback(message)
	assert(not valid, message .. " should be invalid")
end

expect_valid("feat: add commit workflow")
expect_valid("fix(config/nvim): handle missing cz")
expect_valid("feat!: change the API")
expect_valid("refactor(config.nvim/tools): simplify runner")

expect_invalid("update: unsupported type")
expect_invalid("feat(bad@scope): invalid scope")
expect_invalid("feat: ")
expect_invalid("feat: description\nwith body")
expect_invalid("feat: description ")

local function run_git(root, args)
	local command = { "git", "-C", root }
	vim.list_extend(command, args)
	local output = vim.fn.system(command)
	assert(vim.v.shell_error == 0, table.concat(command, " ") .. " failed: " .. output)
end

local function collect_staged(root)
	local result, err
	commit._test.collect_staged_state(root, function(value, message)
		result = value
		err = message
	end)
	assert(
		vim.wait(5000, function()
			return result ~= nil or err ~= nil
		end),
		"timed out collecting staged state"
	)
	assert(result, err)
	return result
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
run_git(root, { "init", "--quiet" })
vim.fn.writefile({ "prepared" }, root .. "/example.txt")
run_git(root, { "add", "-A" })

local prepared = collect_staged(root)
assert(not prepared.empty, "prepared staged state should not be empty")

vim.fn.writefile({ "prepared", "new unstaged work" }, root .. "/example.txt")
local with_unstaged_work = collect_staged(root)
assert(
	with_unstaged_work.fingerprint == prepared.fingerprint,
	"unstaged work should not invalidate a prepared staged snapshot"
)

run_git(root, { "add", "-A" })
local restaged = collect_staged(root)
assert(restaged.fingerprint ~= prepared.fingerprint, "staging new work should invalidate the prepared snapshot")

run_git(root, { "config", "user.email", "codex-test@example.com" })
run_git(root, { "config", "user.name", "Codex Test" })
local bin_dir = root .. "/bin"
vim.fn.mkdir(bin_dir, "p")
local fake_codex = bin_dir .. "/codex"
vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' 'test: prepare commit workflow'" }, fake_codex)
assert((vim.uv or vim.loop).fs_chmod(fake_codex, 493), "failed to make fake codex executable")

local previous_cwd = vim.fn.getcwd()
local previous_path = vim.env.PATH
vim.env.PATH = bin_dir .. ":" .. previous_path
vim.cmd.cd(root)

commit.prepare()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_prepared_commit ~= nil
	end),
	"timed out preparing commit"
)

vim.fn.writefile({ "prepared", "new unstaged work", "later work" }, root .. "/example.txt")
commit.commit()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_prepared_commit == nil
	end),
	"timed out committing prepared snapshot"
)
local committed = vim.fn.system({ "git", "-C", root, "show", "HEAD:example.txt" })
assert(committed == "prepared\nnew unstaged work\n", "commit should exclude work added after preparation")

commit.prepare()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_prepared_commit ~= nil
	end),
	"timed out preparing stale-index test"
)
local old_head = vim.fn.system({ "git", "-C", root, "rev-parse", "HEAD" })
vim.fn.writefile({ "prepared", "new unstaged work", "later work", "restaged work" }, root .. "/example.txt")
run_git(root, { "add", "-A" })
commit.commit()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active
	end),
	"timed out rejecting stale prepared commit"
)
assert(state.codex_prepared_commit == nil, "stale prepared state should be discarded")
local current_head = vim.fn.system({ "git", "-C", root, "rev-parse", "HEAD" })
assert(current_head == old_head, "staged changes after preparation must not be committed")

vim.cmd.cd(previous_cwd)
vim.env.PATH = previous_path
vim.fn.delete(root, "rf")

print("codex_commit_test.lua: ok")
