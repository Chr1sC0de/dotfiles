local context = require("workmux.context")
local prompts = require("workmux.prompts")
local runner = require("workmux.runner")
local state = require("workmux.state")
local util = require("workmux.util")
local worktrees = require("workmux.worktrees")

local M = {}

local function build_prompt_target(opts)
	opts = opts or {}

	if not state.prompt_context_enabled then
		return nil
	end

	if opts.selection or (opts.range and opts.range > 0) then
		local target = context.build_selection_target(opts)
		if target == nil then
			util.notify("no visual selection to add as context", vim.log.levels.WARN)
			return nil
		end
		return target
	end

	return context.build_file_target()
end

---Prompt for a task, then create a Workmux worktree with agent auto-start.
function M.add_prompt(opts)
	local target = build_prompt_target(opts)
	if state.prompt_context_enabled and target == nil then
		return
	end

	prompts.input("Workmux task prompt: ", function(prompt)
		local task_prompt = target and context.build_prompt(prompt, target) or prompt
		runner.run({ "add", "-A", "-p", task_prompt }, { success = "started worktree from prompt" })
	end)
end

---Prompt for a task, then create a Workmux worktree with selected text as context.
function M.add_prompt_selection(opts)
	opts = opts or {}
	opts.selection = true
	M.add_prompt(opts)
end

---Toggle whether Workmux add-from-prompt includes current file/selection context.
function M.toggle_prompt_context()
	state.prompt_context_enabled = not state.prompt_context_enabled
	local status = state.prompt_context_enabled and "enabled" or "disabled"
	util.notify("prompt context " .. status)
end

---Prompt for a branch or worktree name, then create the Workmux worktree.
function M.add_branch()
	prompts.input("Workmux branch/name: ", function(name)
		runner.run({ "add", name }, { success = "started worktree " .. name })
	end)
end

---Select a worktree and open it through Workmux.
function M.open()
	worktrees.select({ prompt = "Open Workmux worktree" }, function(worktree)
		local handle = worktrees.handle(worktree)
		runner.run({ "open", handle }, { success = "opened " .. handle })
	end)
end

---Select a worktree and continue its agent session after opening it.
function M.open_continue()
	worktrees.select({ prompt = "Continue Workmux agent" }, function(worktree)
		local handle = worktrees.handle(worktree)
		runner.run({ "open", handle, "--continue" }, { success = "opened " .. handle .. " with --continue" })
	end)
end

---Open the default Workmux dashboard.
function M.dashboard()
	runner.open_terminal({ "dashboard" })
end

---Open the Workmux dashboard focused on the worktrees tab.
function M.dashboard_worktrees()
	runner.open_terminal({ "dashboard", "--tab", "worktrees" })
end

---Open the Workmux dashboard diff view.
function M.dashboard_diff()
	runner.open_terminal({ "dashboard", "--diff" })
end

---Toggle the Workmux sidebar.
function M.sidebar_toggle()
	runner.run({ "sidebar" }, { success = "toggled sidebar" })
end

---Focus the next agent in the Workmux sidebar.
function M.sidebar_next()
	runner.run({ "sidebar", "next" })
end

---Focus the previous agent in the Workmux sidebar.
function M.sidebar_prev()
	runner.run({ "sidebar", "prev" })
end

---Jump to the most recently done or waiting Workmux agent.
function M.last_done()
	runner.run({ "last-done" })
end

---Select a non-main worktree and close its Workmux window.
function M.close()
	worktrees.select({
		prompt = "Close Workmux window",
		exclude_main = true,
		empty_message = "no non-main worktrees to close",
	}, function(worktree)
		local handle = worktrees.handle(worktree)
		runner.run({ "close", handle }, { success = "closed " .. handle })
	end)
end

---Select a non-main worktree and merge its branch after exact confirmation.
function M.merge()
	worktrees.select({
		prompt = "Merge Workmux branch",
		exclude_main = true,
		empty_message = "no non-main worktrees to merge",
	}, function(worktree)
		local handle = worktrees.handle(worktree)
		local branch = worktrees.branch(worktree)
		if handle ~= nil then
			prompts.confirm_exact(handle, "merge " .. branch, function()
				runner.open_terminal({ "merge", branch })
			end)
		end
	end)
end

---Select a non-main worktree and remove it after exact confirmation.
function M.remove()
	worktrees.select({
		prompt = "Remove Workmux worktree",
		exclude_main = true,
		empty_message = "no non-main worktrees to remove",
	}, function(worktree)
		local handle = worktrees.handle(worktree)
		if handle ~= nil then
			prompts.confirm_exact(handle, "remove " .. handle, function()
				runner.open_terminal({ "remove", handle })
			end)
		end
	end)
end

return M
