vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.o.swapfile = false

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
assert(root ~= "", "a writable temporary directory is required for Git integration tests")
assert(vim.fn.mkdir(root, "p") == 1, "failed to create temporary Git repository")
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
run_git(root, { "config", "commit.gpgsign", "false" })
run_git(root, { "config", "core.hooksPath", root .. "/.git/hooks" })
local previous_executable = vim.fn.executable
vim.fn.executable = function(name)
	if name == "cz" then
		return 0
	end
	return previous_executable(name)
end
local bin_dir = root .. "/.git/bin"
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

-- Exercise the automatic entrypoint with real Git and controlled asynchronous generation.
local notices = {}
local util = require("codex.util")
local previous_notify = util.notify
util.notify = function(message)
	notices[#notices + 1] = message
end
local previous_jobstart = vim.fn.jobstart
local generation_count, add_count = 0, 0
vim.fn.jobstart = function(command, opts)
	if command[1] == "codex" then
		generation_count = generation_count + 1
	elseif command[1] == "git" and command[2] == "add" then
		add_count = add_count + 1
	end
	return previous_jobstart(command, opts)
end

local function wait_finished()
	assert(
		vim.wait(5000, function()
			return not state.codex_commit_active
		end),
		"commit operation should finish and release its active flag"
	)
end

local function git_output(args)
	local command = { "git", "-C", root }
	vim.list_extend(command, args)
	local output = vim.fn.system(command)
	assert(vim.v.shell_error == 0, output)
	return output
end

local function head()
	return git_output({ "rev-parse", "HEAD" })
end

local function fake_script(lines)
	vim.fn.writefile(vim.list_extend({ "#!/bin/sh" }, lines), fake_codex)
end

local function start_delayed()
	vim.fn.delete(root .. "/.git/generation-started")
	vim.fn.delete(root .. "/.git/generation-release")
	fake_script({
		"cat >/dev/null",
		"touch .git/generation-started",
		"attempt=0",
		"while [ ! -f .git/generation-release ]; do",
		"  attempt=$((attempt + 1))",
		'  [ "$attempt" -lt 500 ] || exit 1',
		"  sleep 0.01",
		"done",
		"printf '%s\\n' 'feat: commit saved snapshot'",
	})
	commit.run()
	assert(state.codex_commit_active, "automatic operation should be active before returning")
	assert(
		vim.wait(5000, function()
			return vim.fn.filereadable(root .. "/.git/generation-started") == 1
		end),
		"generation should start asynchronously"
	)
end

local function release_generation()
	vim.fn.writefile({}, root .. "/.git/generation-release")
	wait_finished()
end

-- Seed a tracked deletion, then stage additions and modifications from a subdirectory.
run_git(root, { "add", "-A" })
run_git(root, { "commit", "-m", "test: seed automatic workflow" })
vim.fn.delete(root .. "/stale.txt")
vim.fn.writefile({ "saved snapshot" }, root .. "/example.txt")
vim.fn.writefile({ "new file" }, root .. "/added.txt")
vim.fn.writefile({ "saved buffer" }, root .. "/buffer.txt")
vim.cmd.edit(root .. "/buffer.txt")
local editing_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(editing_buf, 0, -1, false, { "unsaved buffer" })
local editing_win = vim.api.nvim_get_current_win()
vim.fn.mkdir(root .. "/subdir", "p")
vim.cmd.cd(root .. "/subdir")

local before = head()
start_delayed()
local initial_generations, initial_adds = generation_count, add_count
commit.run()
assert(generation_count == initial_generations and add_count == initial_adds, "duplicate run must not launch work")
assert(notices[#notices]:find("already in progress", 1, true), "duplicate should report active operation")
assert(state.codex_commit_active and head() == before, "generation should still be running")
vim.fn.writefile({ "saved snapshot", "later saved edit" }, root .. "/example.txt")
release_generation()
assert(head() ~= before, "automatic flow should create a commit without confirmation")
assert(git_output({ "show", "HEAD:example.txt" }) == "saved snapshot\n", "later saves must stay out of commit")
assert(git_output({ "show", "HEAD:added.txt" }) == "new file\n", "new files should be committed")
assert(git_output({ "ls-tree", "--name-only", "HEAD", "--", "stale.txt" }) == "", "deletions should be committed")
assert(git_output({ "show", "HEAD:buffer.txt" }) == "saved buffer\n", "only saved buffer content should be staged")
assert(vim.bo[editing_buf].modified, "unsaved buffer should remain modified")
assert(vim.api.nvim_buf_get_lines(editing_buf, 0, -1, false)[1] == "unsaved buffer", "unsaved edits must survive")
assert(vim.api.nvim_get_current_win() == editing_win, "automatic commit must not change window focus")
assert(vim.api.nvim_get_current_buf() == editing_buf, "automatic commit must not change buffer focus")
assert(git_output({ "diff", "--", "example.txt" }):find("later saved edit", 1, true), "later work should stay unstaged")
assert(state.codex_prepared_commit == nil, "successful commit should clear prepared state")
assert(
	generation_count == initial_generations and add_count == initial_adds,
	"automatic flow must stage and generate once"
)
for _, message in ipairs(notices) do
	assert(not message:find("Codex commit ready:", 1, true), "automatic flow must not ask for another command")
end
vim.cmd.cd(root)

-- Explicit staging during generation invalidates the candidate without retrying.
before = head()
start_delayed()
vim.fn.writefile({ "restaged during generation" }, root .. "/added.txt")
run_git(root, { "add", "-A" })
local changed = collect_staged(root)
release_generation()
assert(head() == before and state.codex_prepared_commit == nil, "changed index must abort automatic commit")
assert(collect_staged(root).fingerprint == changed.fingerprint, "aborting must preserve staged work")

-- Generation and validation failures must not commit or leave the operation active.
for _, lines in ipairs({
	{ "cat >/dev/null", "echo generation-failed >&2", "exit 1" },
	{ "cat >/dev/null", "printf '%s\\n' 'not a conventional message'" },
	{ "cat >/dev/null", "printf '%s\\n' 'feat: first line' 'feat: second line'" },
}) do
	fake_script(lines)
	commit.run()
	wait_finished()
	assert(head() == before and state.codex_prepared_commit == nil, "failed generation must not commit")
	assert(collect_staged(root).fingerprint == changed.fingerprint, "failure must preserve staged work")
end

-- A failed hook retains the message; retry must neither generate nor stage later edits.
fake_script({ "cat >/dev/null", "printf '%s\\n' 'fix: retry prepared commit'" })
local hook = root .. "/.git/hooks/pre-commit"
vim.fn.writefile({ "#!/bin/sh", "echo hook-rejected >&2", "exit 1" }, hook)
assert((vim.uv or vim.loop).fs_chmod(hook, 493))
commit.run()
wait_finished()
assert(head() == before and state.codex_prepared_commit ~= nil, "hook failure should retain matching candidate")
assert(state.codex_prepared_commit.message == "fix: retry prepared commit", "retry should preserve generated message")
initial_generations, initial_adds = generation_count, add_count
vim.fn.writefile({ "new work after failed hook" }, root .. "/added.txt")
vim.fn.delete(hook)
commit.run()
wait_finished()
assert(head() ~= before and state.codex_prepared_commit == nil, "retry should create commit")
assert(generation_count == initial_generations and add_count == initial_adds, "retry must reuse prepared snapshot")
assert(git_output({ "show", "HEAD:added.txt" }) == "restaged during generation\n", "retry must exclude later work")
assert(git_output({ "log", "-1", "--pretty=%s" }) == "fix: retry prepared commit\n", "retry should use saved message")

-- Reviewed messages are reused by the automatic command, including manual edits.
commit.prepare()
wait_finished()
assert(state.codex_prepared_commit ~= nil, "manual preparation must still stop before commit")
commit.update_message("feat: use reviewed subject", function(ok)
	assert(ok, "reviewed subject should validate")
end)
wait_finished()
initial_generations, initial_adds = generation_count, add_count
commit.run()
wait_finished()
assert(
	git_output({ "log", "-1", "--pretty=%s" }) == "feat: use reviewed subject\n",
	"automatic command should reuse edited subject"
)
assert(
	generation_count == initial_generations and add_count == initial_adds,
	"prepared path must not regenerate or restage"
)

-- Verify command wiring and empty-worktree handling through the public command.
local api = require("codex")
assert(
	api.commit == commit.run and api.commit_prepared == commit.commit,
	"public APIs should preserve prepared-only entrypoint"
)
api.setup()
before = head()
initial_generations, initial_adds = generation_count, add_count
vim.cmd.CodexCommit()
wait_finished()
assert(head() == before and state.codex_prepared_commit == nil, "empty worktree must not create a commit")
assert(
	generation_count == initial_generations and add_count == initial_adds + 1,
	"command should stage but skip empty generation"
)

-- A stale prepared candidate must not silently fall through into fresh preparation.
vim.fn.writefile({ "prepared" }, root .. "/added.txt")
commit.prepare()
wait_finished()
vim.fn.writefile({ "stale prepared" }, root .. "/added.txt")
run_git(root, { "add", "-A" })
initial_generations, initial_adds = generation_count, add_count
vim.cmd.CodexCommit()
wait_finished()
assert(head() == before and state.codex_prepared_commit == nil, "stale prepared candidate must abort")
assert(
	generation_count == initial_generations and add_count == initial_adds,
	"stale candidate must not restart automatically"
)

vim.fn.jobstart = previous_jobstart
vim.fn.executable = previous_executable
util.notify = previous_notify
vim.api.nvim_buf_delete(editing_buf, { force = true })

vim.cmd.cd(previous_cwd)
vim.env.PATH = previous_path
vim.fn.delete(root, "rf")

print("codex_commit_test.lua: ok")
