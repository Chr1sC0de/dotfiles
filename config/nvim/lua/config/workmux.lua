---Workmux command helpers for Neovim keymaps.
---
---This module wraps the `workmux` CLI in Neovim-native prompts, selectors,
---notifications, and terminal windows. Non-interactive commands run through
---`vim.system()` so failures can be reported asynchronously. Interactive TUI
---commands run in FTerm when available, with a terminal tab as the fallback.
local M = {}

---@class WorkmuxWorktree
---@field handle? string Stable workmux handle for the worktree.
---@field branch? string Git branch associated with the worktree.
---@field path? string Filesystem path returned by `workmux list --json`.
---@field is_main? boolean Whether this entry is the main worktree.
---@field is_open? boolean Whether the worktree currently has an open window.
---@field has_uncommitted_changes? boolean Whether the worktree is dirty.

---@class WorkmuxRunResult
---@field code integer Process exit code.
---@field stdout? string Captured stdout when `text = true`.
---@field stderr? string Captured stderr when `text = true`.

---@class WorkmuxRunOptions
---@field success? string Notification text to show after a successful command.
---@field on_success? fun(result: WorkmuxRunResult) Callback after a zero exit code.
---@field on_error? fun(result: WorkmuxRunResult) Callback after a non-zero exit code.

---@class WorkmuxSelectOptions
---@field prompt? string Prompt shown in `vim.ui.select`.
---@field exclude_main? boolean Whether the main worktree should be hidden.
---@field empty_message? string Warning shown when no selectable worktrees remain.

---Show a namespaced Workmux notification.
---
---@param message string
---@param level? integer `vim.log.levels` value.
local function notify(message, level)
	vim.notify("workmux: " .. message, level or vim.log.levels.INFO)
end

---Trim leading and trailing whitespace from optional user or process text.
---
---@param value? string
---@return string
local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

---Check whether the `workmux` executable is available on PATH.
---
---@return boolean
local function has_workmux()
	if vim.fn.executable("workmux") == 1 then
		return true
	end

	notify("workmux executable not found", vim.log.levels.ERROR)
	return false
end

---Build a process argv list for `vim.system()`.
---
---@param args string[]
---@return string[]
local function workmux_argv(args)
	return vim.list_extend({ "workmux" }, args)
end

---Build a human-readable command label for notifications.
---
---@param args string[]
---@return string
local function command_label(args)
	return "workmux " .. table.concat(args, " ")
end

---Shell-escape argv for terminal commands that require a single command string.
---
---@param argv string[]
---@return string
local function shell_join(argv)
	local escaped = {}
	for _, arg in ipairs(argv) do
		table.insert(escaped, vim.fn.shellescape(arg))
	end
	return table.concat(escaped, " ")
end

---Extract the most useful failure text from a completed command.
---
---@param result WorkmuxRunResult
---@return string
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

---Run a non-interactive `workmux` command asynchronously.
---
---Failures are reported with stderr/stdout context. Success notifications and
---callbacks are optional so navigation-style commands can stay quiet.
---
---@param args string[]
---@param opts? WorkmuxRunOptions
local function run(args, opts)
	opts = opts or {}

	if not has_workmux() then
		return
	end

	vim.system(
		workmux_argv(args),
		{ text = true },
		vim.schedule_wrap(function(result)
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
		end)
	)
end

---Open an interactive `workmux` command in a terminal surface.
---
---FTerm gives an embedded floating terminal when the plugin is loaded; the
---plain Neovim terminal tab keeps the command available without that plugin.
---
---@param args string[]
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

---Fetch the current Workmux worktree list and decode the JSON response.
---
---@param callback fun(worktrees: WorkmuxWorktree[])
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

---Format a worktree for picker display.
---
---@param worktree WorkmuxWorktree
---@return string
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

---Return the best identifier to pass to Workmux handle-based commands.
---
---@param worktree WorkmuxWorktree
---@return string?
local function worktree_handle(worktree)
	return worktree.handle or worktree.branch
end

---Return the branch name to pass to branch-oriented Workmux commands.
---
---@param worktree WorkmuxWorktree
---@return string?
local function worktree_branch(worktree)
	return worktree.branch or worktree.handle
end

---Select a worktree and pass the chosen entry to a callback.
---
---@param opts? WorkmuxSelectOptions
---@param callback fun(worktree: WorkmuxWorktree)
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

---Prompt for non-empty user input.
---
---@param prompt string
---@param callback fun(value: string)
local function input(prompt, callback)
	vim.ui.input({ prompt = prompt }, function(value)
		value = trim(value)
		if value == "" then
			return
		end

		callback(value)
	end)
end

---Require an exact typed confirmation before running a destructive action.
---
---@param expected string Confirmation text the user must type exactly.
---@param action string Human-readable action label for the prompt.
---@param callback fun()
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

---Prompt for a task, then create a Workmux worktree with agent auto-start.
function M.add_prompt()
	input("Workmux task prompt: ", function(prompt)
		run({ "add", "-A", "-p", prompt }, { success = "started worktree from prompt" })
	end)
end

---Prompt for a branch or worktree name, then create the Workmux worktree.
function M.add_branch()
	input("Workmux branch/name: ", function(name)
		run({ "add", name }, { success = "started worktree " .. name })
	end)
end

---Select a worktree and open it through Workmux.
function M.open()
	select_worktree({ prompt = "Open Workmux worktree" }, function(worktree)
		local handle = worktree_handle(worktree)
		run({ "open", handle }, { success = "opened " .. handle })
	end)
end

---Select a worktree and continue its agent session after opening it.
function M.open_continue()
	select_worktree({ prompt = "Continue Workmux agent" }, function(worktree)
		local handle = worktree_handle(worktree)
		run({ "open", handle, "--continue" }, { success = "opened " .. handle .. " with --continue" })
	end)
end

---Open the default Workmux dashboard.
function M.dashboard()
	open_terminal({ "dashboard" })
end

---Open the Workmux dashboard focused on the worktrees tab.
function M.dashboard_worktrees()
	open_terminal({ "dashboard", "--tab", "worktrees" })
end

---Open the Workmux dashboard diff view.
function M.dashboard_diff()
	open_terminal({ "dashboard", "--diff" })
end

---Toggle the Workmux sidebar.
function M.sidebar_toggle()
	run({ "sidebar" }, { success = "toggled sidebar" })
end

---Focus the next agent in the Workmux sidebar.
function M.sidebar_next()
	run({ "sidebar", "next" })
end

---Focus the previous agent in the Workmux sidebar.
function M.sidebar_prev()
	run({ "sidebar", "prev" })
end

---Jump to the most recently done or waiting Workmux agent.
function M.last_done()
	run({ "last-done" })
end

---Select a non-main worktree and close its Workmux window.
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

---Select a non-main worktree and merge its branch after exact confirmation.
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

---Select a non-main worktree and remove it after exact confirmation.
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
