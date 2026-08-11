local state = require("codex.state")
local util = require("codex.util")

local M = {}

local MAX_FILE_CONTEXT = 256 * 1024
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

local function read_untracked(root, path)
	local absolute = util.join_path(root, path)
	local stat = (vim.uv or vim.loop).fs_stat(absolute)
	if not stat or stat.type ~= "file" then
		return nil, "untracked path is not a regular file: " .. path
	end
	if stat.size > MAX_FILE_CONTEXT then
		return nil, "untracked file exceeds 256 KiB: " .. path
	end
	local content = table.concat(vim.fn.readfile(absolute, "b"), "\n")
	if content:find("%z") then
		return "[binary file omitted]", nil
	end
	return content, nil
end

local function build_context(root, status, diff, untracked)
	local sections = {
		"Repository: " .. root,
		"",
		"Git status:",
		status,
		"",
		"Tracked diff:",
		diff,
	}
	local total = #table.concat(sections, "\n")
	for _, path in ipairs(untracked) do
		local content, err = read_untracked(root, path)
		if err then
			return nil, err
		end
		table.insert(sections, "")
		table.insert(sections, "Untracked file: " .. path)
		table.insert(sections, content)
		total = total + #path + #content
		if total > MAX_TOTAL_CONTEXT then
			return nil, "change context exceeds 1 MiB"
		end
	end
	if total > MAX_TOTAL_CONTEXT then
		return nil, "change context exceeds 1 MiB"
	end
	return table.concat(sections, "\n"), nil
end

local function collect_state(root, callback)
	run_process({ "git", "status", "--porcelain=v1", "-z" }, { cwd = root }, function(status_code, status, status_err)
		if status_code ~= 0 then
			callback(nil, status_err ~= "" and status_err or "git status failed")
			return
		end
		run_process(
			{ "git", "ls-files", "--others", "--exclude-standard", "-z" },
			{ cwd = root },
			function(files_code, files, files_err)
				if files_code ~= 0 then
					callback(nil, files_err ~= "" and files_err or "git ls-files failed")
					return
				end
				local untracked = {}
				for path in (files .. "\0"):gmatch("(.-)%z") do
					if path ~= "" then
						table.insert(untracked, path)
					end
				end
				run_process(
					{ "git", "diff", "--binary", "--no-ext-diff", "HEAD", "--" },
					{ cwd = root },
					function(diff_code, diff, diff_err)
						local finish = function(combined)
							local context, context_err = build_context(root, status, combined, untracked)
							if not context then
								callback(nil, context_err)
								return
							end
							callback({
								context = context,
								empty = status == "" and combined == "",
								fingerprint = vim.fn.sha256(status .. "\0" .. combined .. "\0" .. context),
							})
						end
						if diff_code == 0 then
							finish(diff)
							return
						end
						-- An unborn branch has no HEAD, so combine its staged and unstaged diffs.
						run_process(
							{ "git", "diff", "--binary", "--no-ext-diff", "--cached", "--" },
							{ cwd = root },
							function(cached_code, cached, cached_err)
								if cached_code ~= 0 then
									callback(nil, diff_err ~= "" and diff_err or cached_err or "git diff failed")
									return
								end
								run_process(
									{ "git", "diff", "--binary", "--no-ext-diff", "--" },
									{ cwd = root },
									function(working_code, working, working_err)
										if working_code ~= 0 then
											callback(nil, working_err ~= "" and working_err or "git diff failed")
											return
										end
										finish(cached .. working)
									end
								)
							end
						)
					end
				)
			end
		)
	end)
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

function M.commit_all()
	if state.codex_commit_active then
		util.notify("A Codex commit is already in progress", vim.log.levels.WARN)
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
	local function abort(message, details)
		finish()
		notify_failure(message, details)
	end

	util.notify("Codex commit: locating Git worktree")
	run_process({ "git", "rev-parse", "--show-toplevel" }, {}, function(code, root, stderr)
		if code ~= 0 then
			abort("current directory is not inside a Git worktree", stderr)
			return
		end
		root = trim(root)
		check_special_state(root, function(ok, reason)
			if not ok then
				abort("cannot commit in the current Git state", reason)
				return
			end
			util.notify("Codex commit: collecting changes")
			collect_state(root, function(snapshot, collect_error)
				if not snapshot then
					abort("could not collect change context", collect_error)
					return
				end
				if snapshot.empty then
					abort("no changes to commit")
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
				util.notify("Codex commit: asking Codex for a message")
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
						util.notify("Codex commit: validating message")
						check_message(root, message, function(valid, validation_error)
							if not valid then
								abort("commit message validation failed", validation_error .. ": " .. message)
								return
							end
							vim.ui.select({ "Commit", "Cancel" }, { prompt = "Commit: " .. message }, function(choice)
								if choice ~= "Commit" then
									finish()
									util.notify("Codex commit cancelled")
									return
								end
								util.notify("Codex commit: checking for changes since context collection")
								collect_state(root, function(current, current_error)
									if not current then
										abort("could not re-check change context", current_error)
										return
									end
									if current.fingerprint ~= snapshot.fingerprint then
										abort("working tree changed; review and retry")
										return
									end
									util.notify("Codex commit: staging all changes")
									run_process({ "git", "add", "-A" }, { cwd = root }, function(add_code, _, add_err)
										if add_code ~= 0 then
											abort("git add failed; staged changes were preserved", add_err)
											return
										end
										run_process(
											{ "git", "rev-parse", "--verify", "HEAD" },
											{ cwd = root },
											function(_, old_head)
												util.notify("Codex commit: running commit and hooks")
												run_process(
													{ "git", "commit", "-m", message },
													{ cwd = root },
													function(commit_code, commit_out, commit_err)
														finish()
														if commit_code == 0 then
															util.notify("Codex commit created: " .. message)
															run_process(
																{ "git", "status", "--short" },
																{ cwd = root },
																function(_, remaining)
																	if remaining ~= "" then
																		util.notify(
																			"Commit succeeded; hooks left additional changes in the worktree",
																			vim.log.levels.WARN
																		)
																	end
																end
															)
															return
														end
														run_process(
															{ "git", "rev-parse", "--verify", "HEAD" },
															{ cwd = root },
															function(_, new_head)
																local details = commit_err ~= "" and commit_err
																	or commit_out
																if
																	trim(new_head) ~= ""
																	and trim(new_head) ~= trim(old_head)
																then
																	notify_failure(
																		"commit was created, but a post-commit hook failed",
																		details
																	)
																else
																	notify_failure(
																		"git commit failed; staged changes were preserved",
																		details
																	)
																end
															end
														)
													end
												)
											end
										)
									end)
								end)
							end)
						end)
					end
				)
			end)
		end)
	end)
end

M._test = { validate_fallback = M.validate_fallback }

return M
