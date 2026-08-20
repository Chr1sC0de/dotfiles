local state = require("workmux.state")

local M = {}

local keymaps = {
	{ "n", "<leader>wa", "add_prompt", "Worktree: add from prompt" },
	{ "x", "<leader>wa", "add_prompt_selection", "Worktree: add from prompt with selection" },
	{ "n", "<leader>wA", "add_branch", "Worktree: add branch" },
	{ "n", "<leader>wo", "open", "Worktree: open" },
	{ "n", "<leader>wO", "open_continue", "Worktree: open and continue agent" },
	{ "n", "<leader>ww", "dashboard_worktrees", "Worktree: browse worktrees" },
	{ "n", "<leader>wd", "dashboard", "Worktree: dashboard or Herdr agents" },
	{ "n", "<leader>wD", "dashboard_diff", "Worktree: dashboard diff" },
	{ "n", "<leader>ws", "sidebar_toggle", "Worktree: toggle sidebar" },
	{ "n", "<leader>wn", "sidebar_next", "Worktree: next agent" },
	{ "n", "<leader>wp", "sidebar_prev", "Worktree: previous agent" },
	{ "n", "<leader>wL", "last_done", "Worktree: latest agent needing attention" },
	{ "n", "<leader>wc", "close", "Worktree: close workspace" },
	{ "n", "<leader>wm", "merge", "Worktree: merge branch" },
	{ "n", "<leader>wr", "remove", "Worktree: remove" },
}

function M.setup(api)
	if state.setup_done then
		return
	end
	state.setup_done = true

	vim.api.nvim_create_user_command("WorktreeAddPrompt", api.add_prompt, { range = true })
	vim.api.nvim_create_user_command("WorktreePromptContextToggle", api.toggle_prompt_context, {})
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
