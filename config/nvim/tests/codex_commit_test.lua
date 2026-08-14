vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")

local commit = require("codex.commit")
local review = require("codex.commit_review")
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

local revision_prompt = commit._test.revision_prompt("staged context", "feat: old message", "use a narrower scope")
assert(revision_prompt:find("feat: old message", 1, true), "revision prompt should include the current message")
assert(revision_prompt:find("use a narrower scope", 1, true), "revision prompt should include reviewer feedback")
assert(revision_prompt:find("staged context", 1, true), "revision prompt should include staged context")

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

commit.prepare()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_prepared_commit ~= nil
	end),
	"timed out preparing commit review"
)

review.open()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and vim.api.nvim_win_is_valid(state.codex_commit_review_win or -1)
	end),
	"timed out opening commit review"
)
local review_lines = table.concat(vim.api.nvim_buf_get_lines(state.codex_commit_review_buf, 0, -1, false), "\n")
assert(review_lines:find(state.codex_prepared_commit.message, 1, true), "review should display the prepared message")
assert(vim.fn.maparg("a", "n", false, true).buffer == 1, "review accept mapping should be buffer-local")
assert(vim.fn.maparg("f", "n", false, true).buffer == 1, "review feedback mapping should be buffer-local")

review.close()
assert(state.codex_prepared_commit ~= nil, "closing review should preserve the prepared message")

review.open()
assert(
	vim.wait(5000, function()
		return vim.api.nvim_win_is_valid(state.codex_commit_review_win or -1)
	end),
	"timed out reopening commit review"
)

local previous_input = vim.ui.input
vim.ui.input = function(opts, callback)
	assert(opts.default == "test: prepare commit workflow", "edit should prefill the prepared message")
	callback("feat: review prepared commit message")
end
review.edit()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_commit_review_status == nil
	end),
	"timed out editing prepared message"
)
assert(
	state.codex_prepared_commit.message == "feat: review prepared commit message",
	"valid edit should replace message"
)

vim.ui.input = function(_, callback)
	callback("invalid message")
end
review.edit()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_commit_review_status == nil
	end),
	"timed out rejecting invalid edit"
)
assert(
	state.codex_prepared_commit.message == "feat: review prepared commit message",
	"invalid edit should preserve previous message"
)

vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' 'fix(nvim): refine commit review message'" }, fake_codex)
vim.ui.input = function(_, callback)
	callback("make the Neovim scope explicit")
end
review.feedback()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_commit_review_status == nil
	end),
	"timed out revising prepared message"
)
assert(
	state.codex_prepared_commit.message == "fix(nvim): refine commit review message",
	"feedback revision should replace prepared message"
)

vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' 'not a conventional commit'" }, fake_codex)
vim.ui.input = function(_, callback)
	callback("try another revision")
end
review.feedback()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_commit_review_status == nil
	end),
	"timed out rejecting invalid feedback revision"
)
assert(
	state.codex_prepared_commit.message == "fix(nvim): refine commit review message",
	"invalid feedback revision should preserve previous message"
)
vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' 'fix(nvim): refine commit review message'" }, fake_codex)
vim.ui.input = previous_input

local before_reject = collect_staged(root)
review.reject()
assert(state.codex_prepared_commit == nil, "reject should clear prepared message")
local after_reject = collect_staged(root)
assert(after_reject.fingerprint == before_reject.fingerprint, "reject should preserve staged changes")

commit.prepare()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_prepared_commit ~= nil
	end),
	"timed out preparing accepted review"
)
review.open()
assert(
	vim.wait(5000, function()
		return vim.api.nvim_win_is_valid(state.codex_commit_review_win or -1)
	end),
	"timed out opening accepted review"
)
review.accept()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_prepared_commit == nil
	end),
	"timed out accepting reviewed commit"
)
local reviewed_subject = vim.fn.system({ "git", "-C", root, "log", "-1", "--pretty=%s" })
assert(reviewed_subject == "fix(nvim): refine commit review message\n", "accept should commit the reviewed message")

vim.fn.writefile({ "review stale state" }, root .. "/stale.txt")
commit.prepare()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active and state.codex_prepared_commit ~= nil
	end),
	"timed out preparing stale review"
)
vim.fn.writefile({ "review stale state", "changed after preparation" }, root .. "/stale.txt")
run_git(root, { "add", "-A" })
review.open()
assert(
	vim.wait(5000, function()
		return not state.codex_commit_active
	end),
	"timed out rejecting stale review"
)
assert(state.codex_prepared_commit == nil, "opening review should discard a stale prepared message")
assert(
	not vim.api.nvim_win_is_valid(state.codex_commit_review_win or -1),
	"stale prepared message should not open review popup"
)

vim.cmd.cd(previous_cwd)
vim.env.PATH = previous_path
vim.fn.delete(root, "rf")

print("codex_commit_test.lua: ok")
