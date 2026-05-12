local prompts = require("workmux.prompts")
local runner = require("workmux.runner")
local worktrees = require("workmux.worktrees")

local M = {}

---Prompt for a task, then create a Workmux worktree with agent auto-start.
function M.add_prompt()
	prompts.input("Workmux task prompt: ", function(prompt)
		runner.run({ "add", "-A", "-p", prompt }, { success = "started worktree from prompt" })
	end)
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
		prompts.confirm_exact(handle, "merge " .. branch, function()
			runner.open_terminal({ "merge", branch })
		end)
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
		prompts.confirm_exact(handle, "remove " .. handle, function()
			runner.open_terminal({ "remove", handle })
		end)
	end)
end

return M
