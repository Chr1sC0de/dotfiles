local M = {}

local function notify(message, level)
	vim.notify("workmux: " .. message, level or vim.log.levels.INFO)
end

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function has_workmux()
	if vim.fn.executable("workmux") == 1 then
		return true
	end

	notify("workmux executable not found", vim.log.levels.ERROR)
	return false
end

local function workmux_argv(args)
	return vim.list_extend({ "workmux" }, args)
end

local function command_label(args)
	return "workmux " .. table.concat(args, " ")
end

local function shell_join(argv)
	local escaped = {}
	for _, arg in ipairs(argv) do
		table.insert(escaped, vim.fn.shellescape(arg))
	end
	return table.concat(escaped, " ")
end

local function failure_message(result)
	local output = trim(result.stderr)
	if output == "" then
		output = trim(result.stdout)
	end
	if output == "" then
		return "exit code " .. result.code
	end
	return output
end

local function run(args, opts)
	opts = opts or {}

	if not has_workmux() then
		return
	end

	vim.system(workmux_argv(args), { text = true }, vim.schedule_wrap(function(result)
		if result.code ~= 0 then
			notify(command_label(args) .. " failed: " .. failure_message(result), vim.log.levels.ERROR)
			if opts.on_error then
				opts.on_error(result)
			end
			return
		end

		if opts.success then
			notify(opts.success)
		end

		if opts.on_success then
			opts.on_success(result)
		end
	end))
end

local function open_terminal(args)
	if not has_workmux() then
		return
	end

	local argv = workmux_argv(args)
	local ok, fterm = pcall(require, "FTerm")
	if ok then
		local term = fterm:new({ auto_close = true })
		term:run(shell_join(argv) .. "; exit")
		return
	end

	vim.cmd("tabnew")
	vim.cmd("terminal " .. shell_join(argv))
	vim.cmd("startinsert")
end

local function list_worktrees(callback)
	run({ "list", "--json" }, {
		on_success = function(result)
			local ok, worktrees = pcall(vim.json.decode, result.stdout)
			if not ok or type(worktrees) ~= "table" then
				notify("could not parse `workmux list --json` output", vim.log.levels.ERROR)
				return
			end

			callback(worktrees)
		end,
	})
end

local function worktree_label(worktree)
	local parts = { worktree.handle or worktree.branch or worktree.path or "unknown" }

	if worktree.branch and worktree.branch ~= worktree.handle then
		table.insert(parts, "(" .. worktree.branch .. ")")
	end

	local status = {}
	if worktree.is_main then
		table.insert(status, "main")
	end
	if worktree.is_open then
		table.insert(status, "open")
	else
		table.insert(status, "closed")
	end
	if worktree.has_uncommitted_changes then
		table.insert(status, "dirty")
	end
	if #status > 0 then
		table.insert(parts, "[" .. table.concat(status, ", ") .. "]")
	end

	return table.concat(parts, " ")
end

local function worktree_handle(worktree)
	return worktree.handle or worktree.branch
end

local function worktree_branch(worktree)
	return worktree.branch or worktree.handle
end

local function select_worktree(opts, callback)
	opts = opts or {}

	list_worktrees(function(worktrees)
		local items = {}
		for _, worktree in ipairs(worktrees) do
			if not opts.exclude_main or not worktree.is_main then
				table.insert(items, worktree)
			end
		end

		if #items == 0 then
			notify(opts.empty_message or "no worktrees found", vim.log.levels.WARN)
			return
		end

		vim.ui.select(items, {
			prompt = opts.prompt or "Workmux worktree",
			format_item = worktree_label,
		}, function(choice)
			if choice then
				callback(choice)
			end
		end)
	end)
end

local function input(prompt, callback)
	vim.ui.input({ prompt = prompt }, function(value)
		value = trim(value)
		if value == "" then
			return
		end

		callback(value)
	end)
end

local function confirm_exact(expected, action, callback)
	vim.ui.input({ prompt = "Type `" .. expected .. "` to " .. action .. ": " }, function(value)
		if value == nil then
			return
		end
		if value ~= expected then
			notify(action .. " cancelled: confirmation did not match", vim.log.levels.WARN)
			return
		end

		callback()
	end)
end

function M.add_prompt()
	input("Workmux task prompt: ", function(prompt)
		run({ "add", "-A", "-p", prompt }, { success = "started worktree from prompt" })
	end)
end

function M.add_branch()
	input("Workmux branch/name: ", function(name)
		run({ "add", name }, { success = "started worktree " .. name })
	end)
end

function M.open()
	select_worktree({ prompt = "Open Workmux worktree" }, function(worktree)
		local handle = worktree_handle(worktree)
		run({ "open", handle }, { success = "opened " .. handle })
	end)
end

function M.open_continue()
	select_worktree({ prompt = "Continue Workmux agent" }, function(worktree)
		local handle = worktree_handle(worktree)
		run({ "open", handle, "--continue" }, { success = "opened " .. handle .. " with --continue" })
	end)
end

function M.dashboard()
	open_terminal({ "dashboard" })
end

function M.dashboard_worktrees()
	open_terminal({ "dashboard", "--tab", "worktrees" })
end

function M.dashboard_diff()
	open_terminal({ "dashboard", "--diff" })
end

function M.sidebar_toggle()
	run({ "sidebar" }, { success = "toggled sidebar" })
end

function M.sidebar_next()
	run({ "sidebar", "next" })
end

function M.sidebar_prev()
	run({ "sidebar", "prev" })
end

function M.last_done()
	run({ "last-done" })
end

function M.close()
	select_worktree({
		prompt = "Close Workmux window",
		exclude_main = true,
		empty_message = "no non-main worktrees to close",
	}, function(worktree)
		local handle = worktree_handle(worktree)
		run({ "close", handle }, { success = "closed " .. handle })
	end)
end

function M.merge()
	select_worktree({
		prompt = "Merge Workmux branch",
		exclude_main = true,
		empty_message = "no non-main worktrees to merge",
	}, function(worktree)
		local handle = worktree_handle(worktree)
		local branch = worktree_branch(worktree)
		confirm_exact(handle, "merge " .. branch, function()
			open_terminal({ "merge", branch })
		end)
	end)
end

function M.remove()
	select_worktree({
		prompt = "Remove Workmux worktree",
		exclude_main = true,
		empty_message = "no non-main worktrees to remove",
	}, function(worktree)
		local handle = worktree_handle(worktree)
		confirm_exact(handle, "remove " .. handle, function()
			open_terminal({ "remove", handle })
		end)
	end)
end

return M
