local runner = require("workmux.runner")
local util = require("workmux.util")

local M = {}

---@class WorkmuxWorktree
---@field handle? string Stable workmux handle for the worktree.
---@field branch? string Git branch associated with the worktree.
---@field path? string Filesystem path returned by `workmux list --json`.
---@field is_main? boolean Whether this entry is the main worktree.
---@field is_open? boolean Whether the worktree currently has an open window.
---@field has_uncommitted_changes? boolean Whether the worktree is dirty.

---@class WorkmuxSelectOptions
---@field prompt? string Prompt shown in `vim.ui.select`.
---@field exclude_main? boolean Whether the main worktree should be hidden.
---@field empty_message? string Warning shown when no selectable worktrees remain.

---Fetch the current Workmux worktree list and decode the JSON response.
---
---@param callback fun(worktrees: WorkmuxWorktree[])
function M.list(callback)
	runner.run({ "list", "--json" }, {
		on_success = function(result)
			local ok, worktrees = pcall(vim.json.decode, result.stdout)
			if not ok or type(worktrees) ~= "table" then
				util.notify("could not parse `workmux list --json` output", vim.log.levels.ERROR)
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
function M.label(worktree)
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
function M.handle(worktree)
	return worktree.handle or worktree.branch
end

---Return the branch name to pass to branch-oriented Workmux commands.
---
---@param worktree WorkmuxWorktree
---@return string?
function M.branch(worktree)
	return worktree.branch or worktree.handle
end

---Select a worktree and pass the chosen entry to a callback.
---
---@param opts? WorkmuxSelectOptions
---@param callback fun(worktree: WorkmuxWorktree)
function M.select(opts, callback)
	opts = opts or {}

	M.list(function(worktrees)
		local items = {}
		for _, worktree in ipairs(worktrees) do
			if not opts.exclude_main or not worktree.is_main then
				table.insert(items, worktree)
			end
		end

		if #items == 0 then
			util.notify(opts.empty_message or "no worktrees found", vim.log.levels.WARN)
			return
		end

		vim.ui.select(items, {
			prompt = opts.prompt or "Workmux worktree",
			format_item = M.label,
		}, function(choice)
			if choice then
				callback(choice)
			end
		end)
	end)
end

return M
