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
	vim.api.nvim_create_user_command("CodexChatBuffers", api.toggle_chat_buffers, {})
	vim.api.nvim_create_user_command("CodexChatNew", api.new_chat, {})
	vim.api.nvim_create_user_command("CodexCommandFile", api.command_file, {})
	vim.api.nvim_create_user_command("CodexCommandFileDiagnostics", api.command_file_diagnostics, {})
	vim.api.nvim_create_user_command("CodexCommandLineDiagnostics", api.command_line_diagnostics, {})
	vim.api.nvim_create_user_command("CodexCommandSelection", api.command_selection, { range = true })
	vim.api.nvim_create_user_command(
		"CodexCommandSelectionDiagnostics",
		api.command_selection_diagnostics,
		{ range = true }
	)
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
	vim.api.nvim_create_user_command("CodexSendFileDiagnostics", api.send_file_diagnostics, {})
	vim.api.nvim_create_user_command("CodexSendLine", api.send_line, {})
	vim.api.nvim_create_user_command("CodexSendLineDiagnostics", api.send_line_diagnostics, {})
	vim.api.nvim_create_user_command("CodexSendParagraph", api.send_paragraph, {})
	vim.api.nvim_create_user_command("CodexSendSelection", api.send_selection, { range = true })
	vim.api.nvim_create_user_command("CodexSendSelectionDiagnostics", api.send_selection_diagnostics, { range = true })

	vim.keymap.set("n", "<leader>aj", api.toggle_jobs, { desc = "Codex: jobs" })
	vim.keymap.set("n", "<leader>aa", api.toggle, { desc = "Codex: toggle chat" })
	vim.keymap.set("n", "<leader>ab", api.toggle_chat_buffers, { desc = "Codex: chat buffers" })
	vim.keymap.set("n", "<leader>an", api.new_chat, { desc = "Codex: new chat" })
	vim.keymap.set("n", "<leader>ac", api.command_file, { desc = "Codex: command over file" })
	vim.keymap.set("x", "<leader>ac", api.command_selection, { desc = "Codex: command over selection" })
	vim.keymap.set("n", "<leader>ae", api.edit_file, { desc = "Codex: edit file" })
	vim.keymap.set("x", "<leader>ae", api.edit_selection, { desc = "Codex: edit selection" })
	vim.keymap.set("n", "<leader>ad", api.send_line_diagnostics, { desc = "Codex: send line diagnostics" })
	vim.keymap.set("x", "<leader>ad", api.send_selection_diagnostics, { desc = "Codex: send selection diagnostics" })
	vim.keymap.set("n", "<leader>aD", api.send_file_diagnostics, { desc = "Codex: send file diagnostics" })
	vim.keymap.set("n", "<leader>af", api.send_file, { desc = "Codex: send file context" })
	vim.keymap.set("n", "<leader>al", api.send_line, { desc = "Codex: send line" })
	vim.keymap.set("n", "<leader>am", api.select_ephemeral_model, { desc = "Codex: ephemeral model" })
	vim.keymap.set("n", "<leader>ap", api.send_paragraph, { desc = "Codex: send paragraph" })
	vim.keymap.set("n", "<leader>ar", api.command_line_diagnostics, { desc = "Codex: command over line diagnostics" })
	vim.keymap.set("x", "<leader>ar", api.command_selection_diagnostics, { desc = "Codex: command over diagnostics" })
	vim.keymap.set("n", "<leader>aR", api.command_file_diagnostics, { desc = "Codex: command over file diagnostics" })
	vim.keymap.set("x", "<leader>as", api.send_selection, { desc = "Codex: send selection" })

	vim.api.nvim_create_autocmd("BufEnter", {
		group = vim.api.nvim_create_augroup("codex-chat-targets", { clear = true }),
		callback = function(event)
			api.activate_buffer(event.buf)
		end,
	})
end

return M
