local spinner = require("opencode.ephemeral.spinner")
local state = require("opencode.state")

local M = {}

function M.setup(api)
	if state.setup_done or vim.g.vscode then
		return
	end
	state.setup_done = true
	spinner.define_signs()

	vim.api.nvim_create_user_command("OpenCodeChat", api.toggle, { desc = "Toggle the OpenCode chat" })
	vim.api.nvim_create_user_command(
		"OpenCodeChatBuffers",
		api.toggle_chat_buffers,
		{ desc = "Toggle OpenCode chat buffers" }
	)
	vim.api.nvim_create_user_command("OpenCodeChatNew", api.new_chat, { desc = "Start a new OpenCode chat" })
	vim.api.nvim_create_user_command(
		"OpenCodeChatAttach",
		api.attach_chat,
		{ desc = "Open the agent attachment dashboard" }
	)
	vim.api.nvim_create_user_command(
		"AgentDashboard",
		api.attach_chat,
		{ desc = "Open the agent attachment dashboard" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeChatResync",
		api.resync_chat_command,
		{ desc = "Resync the OpenCode chat", nargs = "?" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeQuery",
		api.query,
		{ desc = "Ask a read-only question without editor context" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeQueryFile",
		api.query_file,
		{ desc = "Ask a read-only question about the current file" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeQueryFileDiagnostics",
		api.query_file_diagnostics,
		{ desc = "Ask a read-only question using current file diagnostics" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeQueryLineDiagnostics",
		api.query_line_diagnostics,
		{ desc = "Ask a read-only question using current line diagnostics" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeQuerySelection",
		api.query_selection,
		{ desc = "Ask a read-only question about the selected text", range = true }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeQuerySelectionDiagnostics",
		api.query_selection_diagnostics,
		{ desc = "Ask a read-only question using selected text and its diagnostics", range = true }
	)
	vim.api.nvim_create_user_command(
		"OpenCodePrepareCommit",
		api.prepare_commit,
		{ desc = "Stage all changes and prepare a commit message with OpenCode" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeCommit",
		api.commit,
		{ desc = "Commit prepared changes or stage all and generate a commit message" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeReviewCommit",
		api.review_commit,
		{ desc = "Review the commit message prepared by OpenCodePrepareCommit" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeEditFile",
		api.edit_file,
		{ desc = "Apply changes to the current file with OpenCode" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeEditSelection",
		api.edit_selection,
		{ desc = "Apply changes to the selected text with OpenCode", range = true }
	)
	vim.api.nvim_create_user_command("OpenCodeEphemeralModel", api.select_ephemeral_model, {
		complete = function()
			return { "edit", "query" }
		end,
		desc = "Select the ephemeral OpenCode model",
		nargs = "?",
	})
	vim.api.nvim_create_user_command("OpenCodeHealth", api.health, { desc = "Check OpenCode integration health" })
	vim.api.nvim_create_user_command("OpenCodeJobs", api.toggle_jobs, { desc = "Toggle OpenCode jobs" })
	vim.api.nvim_create_user_command("OpenCodeJobsDelete", api.delete_job, { desc = "Delete a OpenCode job", nargs = "?" })
	vim.api.nvim_create_user_command("OpenCodeSendFile", api.send_file, { desc = "Send the current file to OpenCode" })
	vim.api.nvim_create_user_command(
		"OpenCodeSendFileDiagnostics",
		api.send_file_diagnostics,
		{ desc = "Send the current file and its diagnostics to OpenCode" }
	)
	vim.api.nvim_create_user_command("OpenCodeSendLine", api.send_line, { desc = "Send the current line to OpenCode" })
	vim.api.nvim_create_user_command(
		"OpenCodeSendLineDiagnostics",
		api.send_line_diagnostics,
		{ desc = "Send the current line and its diagnostics to OpenCode" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeSendParagraph",
		api.send_paragraph,
		{ desc = "Send the current paragraph to OpenCode" }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeSendSelection",
		api.send_selection,
		{ desc = "Send the selected text to OpenCode", range = true }
	)
	vim.api.nvim_create_user_command(
		"OpenCodeSendSelectionDiagnostics",
		api.send_selection_diagnostics,
		{ desc = "Send selected text and its diagnostics to OpenCode", range = true }
	)

	vim.keymap.set("n", "<leader>aj", api.toggle_jobs, { desc = "OpenCode: toggle background jobs" })
	vim.keymap.set("n", "<leader>aa", api.toggle, { desc = "OpenCode: toggle the chat window" })
	vim.keymap.set("n", "<leader>ab", api.toggle_chat_buffers, { desc = "OpenCode: toggle chat buffers" })
	vim.keymap.set("n", "<leader>an", api.new_chat, { desc = "OpenCode: start a new chat" })
	vim.keymap.set("n", "<leader>aA", api.attach_chat, { desc = "Agents: attachment dashboard" })
	vim.keymap.set(
		"n",
		"<leader>ac",
		api.query_file,
		{ desc = "OpenCode: ask a read-only question about the current file" }
	)
	vim.keymap.set("n", "<leader>aq", api.query, { desc = "OpenCode: ask a read-only question without editor context" })
	vim.keymap.set("n", "<leader>aC", api.commit, { desc = "OpenCode: commit changes" })
	vim.keymap.set(
		"x",
		"<leader>ac",
		api.query_selection,
		{ desc = "OpenCode: ask a read-only question about selected text" }
	)
	vim.keymap.set("n", "<leader>ae", api.edit_file, { desc = "OpenCode: apply changes to the current file" })
	vim.keymap.set("x", "<leader>ae", api.edit_selection, { desc = "OpenCode: apply changes to selected text" })

	vim.keymap.set("n", "<leader>ad", api.send_file_diagnostics, { desc = "OpenCode: send file context and diagnostics" })
	vim.keymap.set(
		"x",
		"<leader>ad",
		api.send_selection_diagnostics,
		{ desc = "OpenCode: send selected text and diagnostics" }
	)
	vim.keymap.set(
		"n",
		"<leader>ar",
		api.query_file_diagnostics,
		{ desc = "OpenCode: ask a read-only question with file diagnostics" }
	)
	vim.keymap.set(
		"x",
		"<leader>ar",
		api.query_selection_diagnostics,
		{ desc = "OpenCode: ask a read-only question with selection diagnostics" }
	)

	vim.keymap.set("n", "<leader>ap", api.send_paragraph, { desc = "OpenCode: send the current paragraph" })

	vim.keymap.set("n", "<leader>as", api.send_file, { desc = "OpenCode: send the current file as context" })
	vim.keymap.set("x", "<leader>as", api.send_selection, { desc = "OpenCode: send selected text" })
	vim.keymap.set("n", "<leader>al", api.send_line, { desc = "OpenCode: send the current line" })

	vim.keymap.set("n", "<leader>aH", api.health, { desc = "OpenCode: check integration health" })
	vim.keymap.set("n", "<leader>am", api.select_ephemeral_model, { desc = "OpenCode: select the ephemeral model" })

	vim.api.nvim_create_autocmd("BufEnter", {
		group = vim.api.nvim_create_augroup("opencode-chat-targets", { clear = true }),
		callback = function(event)
			api.activate_buffer(event.buf)
		end,
	})
end

return M
