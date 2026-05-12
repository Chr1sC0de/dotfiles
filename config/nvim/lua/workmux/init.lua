local actions = require("workmux.actions")
local commands = require("workmux.commands")

local M = {}

M.add_prompt = actions.add_prompt
M.add_branch = actions.add_branch
M.open = actions.open
M.open_continue = actions.open_continue
M.dashboard = actions.dashboard
M.dashboard_worktrees = actions.dashboard_worktrees
M.dashboard_diff = actions.dashboard_diff
M.sidebar_toggle = actions.sidebar_toggle
M.sidebar_next = actions.sidebar_next
M.sidebar_prev = actions.sidebar_prev
M.last_done = actions.last_done
M.close = actions.close
M.merge = actions.merge
M.remove = actions.remove

function M.setup()
	commands.setup(M)
end

return M
