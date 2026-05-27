local state = require("workmux.state")

local M = {}

local keymaps = {
	{ "n", "<leader>wa", "add_prompt", "Workmux: add from prompt" },
	{ "x", "<leader>wa", "add_prompt_selection", "Workmux: add from prompt with selection" },
	{ "n", "<leader>wA", "add_branch", "Workmux: add branch" },
	{ "n", "<leader>wo", "open", "Workmux: open worktree" },
	{ "n", "<leader>wO", "open_continue", "Workmux: open and continue agent" },
	{ "n", "<leader>ww", "dashboard_worktrees", "Workmux: dashboard worktrees" },
	{ "n", "<leader>wd", "dashboard", "Workmux: dashboard" },
	{ "n", "<leader>wD", "dashboard_diff", "Workmux: dashboard diff" },
	{ "n", "<leader>ws", "sidebar_toggle", "Workmux: toggle sidebar" },
	{ "n", "<leader>wn", "sidebar_next", "Workmux: next agent" },
	{ "n", "<leader>wp", "sidebar_prev", "Workmux: previous agent" },
	{ "n", "<leader>wL", "last_done", "Workmux: last done agent" },
	{ "n", "<leader>wc", "close", "Workmux: close window" },
	{ "n", "<leader>wm", "merge", "Workmux: merge branch" },
	{ "n", "<leader>wr", "remove", "Workmux: remove worktree" },
}

function M.setup(api)
	if state.setup_done then
		return
	end
	state.setup_done = true

	vim.api.nvim_create_user_command("WorkmuxAddPrompt", api.add_prompt, { range = true })
	vim.api.nvim_create_user_command("WorkmuxPromptContextToggle", api.toggle_prompt_context, {})

	for _, keymap in ipairs(keymaps) do
		local mode = keymap[1]
		local lhs = keymap[2]
		local action = keymap[3]
		local desc = keymap[4]
		vim.keymap.set(mode, lhs, api[action], { desc = desc })
	end
end

return M
