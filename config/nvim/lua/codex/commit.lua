local state = require("codex.state")
local util = require("codex.util")

local M = {}

local MAX_TOTAL_CONTEXT = 1024 * 1024

local allowed_types = {
	build = true,
	chore = true,
	ci = true,
	docs = true,
	feat = true,
	fix = true,
	perf = true,
	refactor = true,
	revert = true,
	style = true,
	test = true,
}

local function trim(value)
	return tostring(value or ""):gsub("\r", ""):match("^%s*(.-)%s*$")
end

local function append_output(target, data)
	if data then
		for _, line in ipairs(data) do
			if line ~= "" then
				table.insert(target, line)
			end
		end
	end
end

local function run_process(command, opts, callback)
	opts = opts or {}
	local stdout, stderr = {}, {}
	local job_id = vim.fn.jobstart(command, {
		cwd = opts.cwd,
		stdin = opts.input and "pipe" or "null",
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			append_output(stdout, data)
		end,
		on_stderr = function(_, data)
			append_output(stderr, data)
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				callback(code, table.concat(stdout, "\n"), table.concat(stderr, "\n"))
			end)
		end,
	})

	if job_id <= 0 then
		callback(nil, "", "failed to start process")
		return nil
	end

	if opts.input then
		vim.fn.chansend(job_id, opts.input)
		vim.fn.chanclose(job_id, "stdin")
	end
	return job_id
end

local function notify_failure(message, details)
	if details and details ~= "" then
		message = message .. ": " .. util.trim_display(details:gsub("%s+", " "), 240)
	end
	util.notify(message, vim.log.levels.ERROR)
end

local function collect_staged_state(root, callback)
	run_process(
		{ "git", "diff", "--cached", "--binary", "--no-ext-diff", "--" },
		{ cwd = root },
		function(code, diff, stderr)
			if code ~= 0 then
				callback(nil, stderr ~= "" and stderr or "git diff --cached failed")
				return
			end
			if #diff > MAX_TOTAL_CONTEXT then
				callback(nil, "staged change context exceeds 1 MiB")
				return
			end
			callback({
				context = table.concat({ "Repository: " .. root, "", "Staged diff:", diff }, "\n"),
				empty = diff == "",
				fingerprint = vim.fn.sha256(diff),
			})
		end
	)
end

local function valid_scope(scope)
	return scope == nil or scope:match("^[%w%._/%- ]+$") ~= nil
end

function M.validate_fallback(message)
	message = tostring(message or "")
	if message ~= trim(message) then
		return false, "message must not have surrounding whitespace"
	end
	if message:find("[\r\n]") then
		return false, "message must be a single line"
	end
	local commit_type, scope, breaking, description = message:match("^(%a[%w-]*)(%b())(!?): (.+)$")
	if not commit_type then
		commit_type, breaking, description = message:match("^(%a[%w-]*)(!): (.+)$")
	end
	if not commit_type then
		commit_type, description = message:match("^(%a[%w-]*): (.+)$")
		breaking = ""
	end
	if not commit_type or not allowed_types[commit_type] then
		return false, "expected an allowed Conventional Commit type"
	end
	if not valid_scope(scope and scope:sub(2, -2)) then
		return false, "scope contains unsupported characters"
	end
	if description:match("^%s") or description:match("%s$") then
		return false, "description must not have surrounding whitespace"
	end
	return true
end

local function extract_message(output)
	local messages = {}
	for line in (output:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
		if trim(line) ~= "" then
			table.insert(messages, trim(line))
		end
	end
	if #messages ~= 1 then
		return nil, "Codex must return exactly one non-empty commit subject"
	end
	return messages[1]
end

local function check_message(root, message, callback)
	if vim.fn.executable("cz") == 1 then
		run_process({ "cz", "check", "--message", message }, { cwd = root }, function(code, _, stderr)
			callback(code == 0, stderr ~= "" and stderr or "Commitizen rejected the message")
		end)
		return
	end
	local valid, reason = M.validate_fallback(message)
	callback(valid, reason)
end

local function check_special_state(root, callback)
	run_process({ "git", "rev-parse", "--git-dir" }, { cwd = root }, function(code, git_dir, stderr)
		if code ~= 0 then
			callback(false, stderr ~= "" and stderr or "unable to resolve Git directory")
			return
		end
		git_dir = trim(git_dir)
		if not git_dir:match("^/") then
			git_dir = util.join_path(root, git_dir)
		end
		for _, marker in ipairs({
			{ "MERGE_HEAD", "merge" },
			{ "CHERRY_PICK_HEAD", "cherry-pick" },
			{ "REVERT_HEAD", "revert" },
		}) do
			if vim.fn.filereadable(util.join_path(git_dir, marker[1])) == 1 then
				callback(false, "an in-progress " .. marker[2] .. " is present")
				return
			end
		end
		if
			vim.fn.isdirectory(util.join_path(git_dir, "rebase-merge")) == 1
			or vim.fn.isdirectory(util.join_path(git_dir, "rebase-apply")) == 1
		then
			callback(false, "an in-progress rebase is present")
			return
		end
		callback(true)
	end)
end

local function finish()
	state.codex_commit_active = false
end

local function invalidate_prepared(message)
	state.codex_prepared_commit = nil
	finish()
	util.notify(message, vim.log.levels.WARN)
end

function M.prepare()
	if state.codex_commit_active then
		util.notify("A Codex commit operation is already in progress", vim.log.levels.WARN)
		return
	end
	if vim.fn.executable("git") ~= 1 then
		notify_failure("git executable was not found")
		return
	end
	if vim.fn.executable("codex") ~= 1 then
		notify_failure("codex executable was not found")
		return
	end

	state.codex_commit_active = true
	state.codex_prepared_commit = nil
	local function abort(message, details)
		finish()
		notify_failure(message, details)
	end

	util.notify("Codex commit: staging changes for preparation")
	run_process({ "git", "rev-parse", "--show-toplevel" }, {}, function(code, root, stderr)
		if code ~= 0 then
			abort("current directory is not inside a Git worktree", stderr)
			return
		end
		root = trim(root)
		check_special_state(root, function(ok, reason)
			if not ok then
				abort("cannot prepare a commit in the current Git state", reason)
				return
			end
			run_process({ "git", "add", "-A" }, { cwd = root }, function(add_code, _, add_err)
				if add_code ~= 0 then
					abort("git add failed; existing staged changes were preserved", add_err)
					return
				end
				collect_staged_state(root, function(snapshot, collect_error)
					if not snapshot then
						abort("could not collect staged change context", collect_error)
						return
					end
					if snapshot.empty then
						abort("no changes to prepare")
						return
					end
					local prompt = table.concat({
						"You are generating a Git commit message.",
						"Do not edit files, run git commands, or perform any other action.",
						"Return exactly one line in Conventional Commit format:",
						"type(optional-scope): imperative description",
						"Allowed types: build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test.",
						"An optional ! may mark a breaking change. Return no Markdown, quotes, explanation, or body.",
						"",
						snapshot.context,
					}, "\n")
					run_process(
						{ "codex", "exec", "--ephemeral", "--sandbox", "read-only", "--cd", root, "-" },
						{ cwd = root, input = prompt },
						function(codex_code, stdout, codex_stderr)
							if codex_code ~= 0 then
								abort("Codex failed", codex_stderr ~= "" and codex_stderr or stdout)
								return
							end
							local message, message_error = extract_message(stdout)
							if not message then
								abort("Codex returned an invalid commit message", message_error .. ": " .. stdout)
								return
							end
							check_message(root, message, function(valid, validation_error)
								if not valid then
									abort("commit message validation failed", validation_error .. ": " .. message)
									return
								end
								collect_staged_state(root, function(current, current_error)
									if not current then
										abort("could not re-check staged changes", current_error)
										return
									end
									if current.fingerprint ~= snapshot.fingerprint then
										invalidate_prepared(
											"Staged changes changed during preparation; run :CodexPrepareCommit again"
										)
										return
									end
									state.codex_prepared_commit = {
										root = root,
										message = message,
										fingerprint = snapshot.fingerprint,
									}
									finish()
									util.notify("Codex commit ready: " .. message .. " — run :CodexCommit")
								end)
							end)
						end
					)
				end)
			end)
		end)
	end)
end

function M.commit()
	if state.codex_commit_active then
		util.notify("Codex commit preparation is still in progress", vim.log.levels.WARN)
		return
	end
	local prepared = state.codex_prepared_commit
	if not prepared then
		util.notify("No prepared commit; run :CodexPrepareCommit first", vim.log.levels.WARN)
		return
	end
	if vim.fn.executable("git") ~= 1 then
		notify_failure("git executable was not found")
		return
	end

	state.codex_commit_active = true
	check_special_state(prepared.root, function(ok, reason)
		if not ok then
			invalidate_prepared("Cannot commit in the current Git state: " .. tostring(reason))
			return
		end
		collect_staged_state(prepared.root, function(current, current_error)
			if not current then
				finish()
				notify_failure("could not check prepared staged changes", current_error)
				return
			end
			if current.fingerprint ~= prepared.fingerprint then
				invalidate_prepared("Staged changes no longer match; run :CodexPrepareCommit again")
				return
			end
			run_process({ "git", "rev-parse", "--verify", "HEAD" }, { cwd = prepared.root }, function(_, old_head)
				util.notify("Codex commit: running commit and hooks")
				run_process(
					{ "git", "commit", "-m", prepared.message },
					{ cwd = prepared.root },
					function(commit_code, commit_out, commit_err)
						if commit_code == 0 then
							state.codex_prepared_commit = nil
							finish()
							util.notify("Codex commit created: " .. prepared.message)
							run_process({ "git", "status", "--short" }, { cwd = prepared.root }, function(_, remaining)
								if remaining ~= "" then
									util.notify(
										"Commit succeeded; additional changes remain in the worktree",
										vim.log.levels.WARN
									)
								end
							end)
							return
						end
						run_process(
							{ "git", "rev-parse", "--verify", "HEAD" },
							{ cwd = prepared.root },
							function(_, new_head)
								local details = commit_err ~= "" and commit_err or commit_out
								if trim(new_head) ~= "" and trim(new_head) ~= trim(old_head) then
									state.codex_prepared_commit = nil
									finish()
									notify_failure("commit was created, but a post-commit hook failed", details)
									return
								end
								collect_staged_state(prepared.root, function(after, after_error)
									if not after or after.fingerprint ~= prepared.fingerprint then
										state.codex_prepared_commit = nil
									end
									finish()
									local retry = state.codex_prepared_commit and "; run :CodexCommit to retry"
										or "; run :CodexPrepareCommit again"
									notify_failure(
										"git commit failed; staged changes were preserved" .. retry,
										after_error or details
									)
								end)
							end
						)
					end
				)
			end)
		end)
	end)
end

M._test = {
	collect_staged_state = collect_staged_state,
	validate_fallback = M.validate_fallback,
}

return M
