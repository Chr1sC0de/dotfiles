local spinner = require("codex.ephemeral.spinner")
local state = require("codex.state")

local M = {}

function M.setup(api)
	if state.setup_done or vim.g.vscode then
		return
	end
	state.setup_done = true
	spinner.define_signs()

	vim.api.nvim_create_user_command("CodexChat", api.toggle, {})
	vim.api.nvim_create_user_command("CodexCommandFile", api.command_file, {})
	vim.api.nvim_create_user_command("CodexCommandSelection", api.command_selection, { range = true })
	vim.api.nvim_create_user_command("CodexEditFile", api.edit_file, {})
	vim.api.nvim_create_user_command("CodexEditSelection", api.edit_selection, { range = true })
	vim.api.nvim_create_user_command("CodexEphemeralModel", api.select_ephemeral_model, {
		complete = function()
			return { "edit", "command" }
		end,
		nargs = "?",
	})
	vim.api.nvim_create_user_command("CodexJobs", api.toggle_jobs, {})
	vim.api.nvim_create_user_command("CodexJobsDelete", api.delete_job, { nargs = "?" })
	vim.api.nvim_create_user_command("CodexSendFile", api.send_file, {})
	vim.api.nvim_create_user_command("CodexSendLine", api.send_line, {})
	vim.api.nvim_create_user_command("CodexSendParagraph", api.send_paragraph, {})
	vim.api.nvim_create_user_command("CodexSendSelection", api.send_selection, { range = true })

	vim.keymap.set("n", "<leader>aj", api.toggle_jobs, { desc = "Codex: jobs" })
	vim.keymap.set("n", "<leader>aa", api.toggle, { desc = "Codex: toggle chat" })
	vim.keymap.set("n", "<leader>ac", api.command_file, { desc = "Codex: command over file" })
	vim.keymap.set("x", "<leader>ac", api.command_selection, { desc = "Codex: command over selection" })
	vim.keymap.set("n", "<leader>ae", api.edit_file, { desc = "Codex: edit file" })
	vim.keymap.set("x", "<leader>ae", api.edit_selection, { desc = "Codex: edit selection" })
	vim.keymap.set("n", "<leader>af", api.send_file, { desc = "Codex: send file context" })
	vim.keymap.set("n", "<leader>al", api.send_line, { desc = "Codex: send line" })
	vim.keymap.set("n", "<leader>am", api.select_ephemeral_model, { desc = "Codex: ephemeral model" })
	vim.keymap.set("n", "<leader>ap", api.send_paragraph, { desc = "Codex: send paragraph" })
	vim.keymap.set("x", "<leader>as", api.send_selection, { desc = "Codex: send selection" })
end

return M
