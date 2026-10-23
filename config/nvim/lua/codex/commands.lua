local spinner = require("codex.ephemeral.spinner")
local state = require("codex.state")

local M = {}

function M.setup(api)
	if state.setup_done or vim.g.vscode then
		return
	end
	state.setup_done = true
	spinner.define_signs()

	vim.api.nvim_create_user_command("CodexChat", api.toggle, { desc = "Toggle the Codex chat" })
	vim.api.nvim_create_user_command(
		"CodexChatBuffers",
		api.toggle_chat_buffers,
		{ desc = "Toggle Codex chat buffers" }
	)
	vim.api.nvim_create_user_command("CodexChatNew", api.new_chat, { desc = "Start a new Codex chat" })
	vim.api.nvim_create_user_command(
		"CodexChatAttach",
		api.attach_chat,
		{ desc = "Attach a surviving Herdr Codex agent" }
	)
	vim.api.nvim_create_user_command(
		"CodexChatResync",
		api.resync_chat_command,
		{ desc = "Resync the Codex chat", nargs = "?" }
	)
	vim.api.nvim_create_user_command(
		"CodexQuery",
		api.query,
		{ desc = "Ask a read-only question without editor context" }
	)
	vim.api.nvim_create_user_command(
		"CodexQueryFile",
		api.query_file,
		{ desc = "Ask a read-only question about the current file" }
	)
	vim.api.nvim_create_user_command(
		"CodexQueryFileDiagnostics",
		api.query_file_diagnostics,
		{ desc = "Ask a read-only question using current file diagnostics" }
	)
	vim.api.nvim_create_user_command(
		"CodexQueryLineDiagnostics",
		api.query_line_diagnostics,
		{ desc = "Ask a read-only question using current line diagnostics" }
	)
	vim.api.nvim_create_user_command(
		"CodexQuerySelection",
		api.query_selection,
		{ desc = "Ask a read-only question about the selected text", range = true }
	)
	vim.api.nvim_create_user_command(
		"CodexQuerySelectionDiagnostics",
		api.query_selection_diagnostics,
		{ desc = "Ask a read-only question using selected text and its diagnostics", range = true }
	)
	vim.api.nvim_create_user_command(
		"CodexPrepareCommit",
		api.prepare_commit,
		{ desc = "Stage all changes and prepare a commit message with Codex" }
	)
	vim.api.nvim_create_user_command(
		"CodexCommit",
		api.commit,
		{ desc = "Commit prepared changes or stage all and generate a commit message" }
	)
	vim.api.nvim_create_user_command(
		"CodexReviewCommit",
		api.review_commit,
		{ desc = "Review the commit message prepared by CodexPrepareCommit" }
	)
	vim.api.nvim_create_user_command(
		"CodexEditFile",
		api.edit_file,
		{ desc = "Apply changes to the current file with Codex" }
	)
	vim.api.nvim_create_user_command(
		"CodexEditSelection",
		api.edit_selection,
		{ desc = "Apply changes to the selected text with Codex", range = true }
	)
	vim.api.nvim_create_user_command("CodexEphemeralModel", api.select_ephemeral_model, {
		complete = function()
			return { "edit", "query" }
		end,
		desc = "Select the ephemeral Codex model",
		nargs = "?",
	})
	vim.api.nvim_create_user_command("CodexHealth", api.health, { desc = "Check Codex integration health" })
	vim.api.nvim_create_user_command("CodexJobs", api.toggle_jobs, { desc = "Toggle Codex jobs" })
	vim.api.nvim_create_user_command("CodexJobsDelete", api.delete_job, { desc = "Delete a Codex job", nargs = "?" })
	vim.api.nvim_create_user_command("CodexSendFile", api.send_file, { desc = "Send the current file to Codex" })
	vim.api.nvim_create_user_command(
		"CodexSendFileDiagnostics",
		api.send_file_diagnostics,
		{ desc = "Send the current file and its diagnostics to Codex" }
	)
	vim.api.nvim_create_user_command("CodexSendLine", api.send_line, { desc = "Send the current line to Codex" })
	vim.api.nvim_create_user_command(
		"CodexSendLineDiagnostics",
		api.send_line_diagnostics,
		{ desc = "Send the current line and its diagnostics to Codex" }
	)
	vim.api.nvim_create_user_command(
		"CodexSendParagraph",
		api.send_paragraph,
		{ desc = "Send the current paragraph to Codex" }
	)
	vim.api.nvim_create_user_command(
		"CodexSendSelection",
		api.send_selection,
		{ desc = "Send the selected text to Codex", range = true }
	)
	vim.api.nvim_create_user_command(
		"CodexSendSelectionDiagnostics",
		api.send_selection_diagnostics,
		{ desc = "Send selected text and its diagnostics to Codex", range = true }
	)

	vim.keymap.set("n", "<leader>aj", api.toggle_jobs, { desc = "Codex: toggle background jobs" })
	vim.keymap.set("n", "<leader>aa", api.toggle, { desc = "Codex: toggle the chat window" })
	vim.keymap.set("n", "<leader>ab", api.toggle_chat_buffers, { desc = "Codex: toggle chat buffers" })
	vim.keymap.set("n", "<leader>an", api.new_chat, { desc = "Codex: start a new chat" })
	vim.keymap.set("n", "<leader>aA", api.attach_chat, { desc = "Codex: attach a Herdr agent" })
	vim.keymap.set(
		"n",
		"<leader>ac",
		api.query_file,
		{ desc = "Codex: ask a read-only question about the current file" }
	)
	vim.keymap.set("n", "<leader>aq", api.query, { desc = "Codex: ask a read-only question without editor context" })
	vim.keymap.set("n", "<leader>aC", api.commit, { desc = "Codex: commit changes" })
	vim.keymap.set(
		"x",
		"<leader>ac",
		api.query_selection,
		{ desc = "Codex: ask a read-only question about selected text" }
	)
	vim.keymap.set("n", "<leader>ae", api.edit_file, { desc = "Codex: apply changes to the current file" })
	vim.keymap.set("x", "<leader>ae", api.edit_selection, { desc = "Codex: apply changes to selected text" })

	vim.keymap.set("n", "<leader>ad", api.send_file_diagnostics, { desc = "Codex: send file context and diagnostics" })
	vim.keymap.set(
		"x",
		"<leader>ad",
		api.send_selection_diagnostics,
		{ desc = "Codex: send selected text and diagnostics" }
	)
	vim.keymap.set(
		"n",
		"<leader>ar",
		api.query_file_diagnostics,
		{ desc = "Codex: ask a read-only question with file diagnostics" }
	)
	vim.keymap.set(
		"x",
		"<leader>ar",
		api.query_selection_diagnostics,
		{ desc = "Codex: ask a read-only question with selection diagnostics" }
	)

	vim.keymap.set("n", "<leader>ap", api.send_paragraph, { desc = "Codex: send the current paragraph" })

	vim.keymap.set("n", "<leader>as", api.send_file, { desc = "Codex: send the current file as context" })
	vim.keymap.set("x", "<leader>as", api.send_selection, { desc = "Codex: send selected text" })
	vim.keymap.set("n", "<leader>al", api.send_line, { desc = "Codex: send the current line" })

	vim.keymap.set("n", "<leader>aH", api.health, { desc = "Codex: check integration health" })
	vim.keymap.set("n", "<leader>am", api.select_ephemeral_model, { desc = "Codex: select the ephemeral model" })

	vim.api.nvim_create_autocmd("BufEnter", {
		group = vim.api.nvim_create_augroup("codex-chat-targets", { clear = true }),
		callback = function(event)
			api.activate_buffer(event.buf)
		end,
	})
end

return M
