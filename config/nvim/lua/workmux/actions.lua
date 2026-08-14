local context = require("workmux.context")
local herdr = require("workmux.herdr")
local prompts = require("workmux.prompts")
local runner = require("workmux.runner")
local state = require("workmux.state")
local util = require("workmux.util")
local worktrees = require("workmux.worktrees")

local M = { _test = {} }

local function active_backend()
	if vim.env.HERDR_ENV == "1" then
		if herdr.available() then
			return "herdr"
		end
		util.notify("Herdr environment is active but its workspace context or CLI is unavailable", vim.log.levels.ERROR)
		return nil
	end
	if vim.env.TMUX ~= nil and vim.env.TMUX ~= "" then
		return "workmux"
	end
	util.notify("not running inside Herdr or tmux", vim.log.levels.ERROR)
	return nil
end

M._test.active_backend = active_backend

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

---Prompt for a task, then create a routed worktree with an agent.
function M.add_prompt(opts)
	local backend = active_backend()
	if backend == nil then
		return
	end
	local target = build_prompt_target(opts)
	if state.prompt_context_enabled and target == nil then
		return
	end

	prompts.input("Worktree task prompt: ", function(prompt)
		local task_prompt = target and context.build_prompt(prompt, target) or prompt
		if backend == "herdr" then
			herdr.add_prompt(task_prompt)
		else
			runner.run({ "add", "-A", "-p", task_prompt }, { success = "started worktree from prompt" })
		end
	end)
end

---Prompt for a task, then create a routed worktree with selected text as context.
function M.add_prompt_selection(opts)
	opts = opts or {}
	opts.selection = true
	M.add_prompt(opts)
end

---Toggle whether add-from-prompt includes current file/selection context.
function M.toggle_prompt_context()
	state.prompt_context_enabled = not state.prompt_context_enabled
	local status = state.prompt_context_enabled and "enabled" or "disabled"
	util.notify("prompt context " .. status)
end

---Prompt for a branch or worktree name, then create it through the active backend.
function M.add_branch()
	local backend = active_backend()
	if backend == nil then
		return
	end
	prompts.input("Worktree branch/name: ", function(name)
		if backend == "herdr" then
			herdr.add_branch(name)
		else
			runner.run({ "add", name }, { success = "started worktree " .. name })
		end
	end)
end

---Select a worktree and open it through the active backend.
function M.open()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.open(false)
		return
	end
	if backend == nil then
		return
	end
	worktrees.select({ prompt = "Open Workmux worktree" }, function(worktree)
		local handle = worktrees.handle(worktree)
		runner.run({ "open", handle }, { success = "opened " .. handle })
	end)
end

---Select a worktree and continue its agent session after opening it.
function M.open_continue()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.open(true)
		return
	end
	if backend == nil then
		return
	end
	worktrees.select({ prompt = "Continue Workmux agent" }, function(worktree)
		local handle = worktrees.handle(worktree)
		runner.run({ "open", handle, "--continue" }, { success = "opened " .. handle .. " with --continue" })
	end)
end

---Open the active backend's workspace overview.
function M.dashboard()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.select_workspace()
		return
	end
	if backend == nil then
		return
	end
	runner.open_terminal({ "dashboard" })
end

---Open the active backend's worktree overview.
function M.dashboard_worktrees()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.open(false)
		return
	end
	if backend == nil then
		return
	end
	runner.open_terminal({ "dashboard", "--tab", "worktrees" })
end

---Open the active backend's diff overview when supported.
function M.dashboard_diff()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.unsupported("dashboard diff", "use a Git diff tool in the worktree")
		return
	end
	if backend == nil then
		return
	end
	runner.open_terminal({ "dashboard", "--diff" })
end

---Toggle the active backend's sidebar when supported.
function M.sidebar_toggle()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.unsupported("sidebar control", "use Herdr's native prefix+b sidebar")
		return
	end
	if backend == nil then
		return
	end
	runner.run({ "sidebar" }, { success = "toggled sidebar" })
end

---Focus the next agent.
function M.sidebar_next()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.cycle_agent(1)
		return
	end
	if backend == nil then
		return
	end
	runner.run({ "sidebar", "next" })
end

---Focus the previous agent.
function M.sidebar_prev()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.cycle_agent(-1)
		return
	end
	if backend == nil then
		return
	end
	runner.run({ "sidebar", "prev" })
end

---Jump to the most recent agent needing attention.
function M.last_done()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.focus_latest_attention()
		return
	end
	if backend == nil then
		return
	end
	runner.run({ "last-done" })
end

---Select a non-main worktree and close its workspace.
function M.close()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.close()
		return
	end
	if backend == nil then
		return
	end
	worktrees.select({
		prompt = "Close Workmux window",
		exclude_main = true,
		empty_message = "no non-main worktrees to close",
	}, function(worktree)
		local handle = worktrees.handle(worktree)
		runner.run({ "close", handle }, { success = "closed " .. handle })
	end)
end

---Select a non-main worktree and merge its branch when supported.
function M.merge()
	local backend = active_backend()
	if backend == "herdr" then
		herdr.unsupported("merge", "run the Git merge explicitly or use Workmux from tmux")
		return
	end
	if backend == nil then
		return
	end
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
	local backend = active_backend()
	if backend == "herdr" then
		herdr.remove()
		return
	end
	if backend == nil then
		return
	end
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
