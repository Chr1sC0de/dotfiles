local util = require("workmux.util")

local M = {}

---@class WorkmuxRunResult
---@field code integer Process exit code.
---@field stdout? string Captured stdout when `text = true`.
---@field stderr? string Captured stderr when `text = true`.

---@class WorkmuxRunOptions
---@field success? string Notification text to show after a successful command.
---@field on_success? fun(result: WorkmuxRunResult) Callback after a zero exit code.
---@field on_error? fun(result: WorkmuxRunResult) Callback after a non-zero exit code.

---Check whether the `workmux` executable is available on PATH.
---
---@return boolean
local function has_workmux()
	if vim.fn.executable("workmux") == 1 then
		return true
	end

	util.notify("workmux executable not found", vim.log.levels.ERROR)
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
	local output = util.trim(result.stderr)
	if output == "" then
		output = util.trim(result.stdout)
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
function M.run(args, opts)
	opts = opts or {}

	if not has_workmux() then
		return
	end

	vim.system(
		workmux_argv(args),
		{ text = true },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 then
				util.notify(command_label(args) .. " failed: " .. failure_message(result), vim.log.levels.ERROR)
				if opts.on_error then
					opts.on_error(result)
				end
				return
			end

			if opts.success then
				util.notify(opts.success)
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
function M.open_terminal(args)
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

return M
