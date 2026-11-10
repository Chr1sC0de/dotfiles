local spinner = require("agents.ephemeral.spinner")
local state = require("agents.state")

local M = {}

-- Keep the old commands as aliases, including their ranges and completion.
local function command(name, action, opts)
	vim.api.nvim_create_user_command(name, action, opts)
	if name:match("^OpenCode") then
		local neutral = name:gsub("^OpenCode", "Agent")
		if vim.fn.exists(":" .. neutral) == 0 then
			vim.api.nvim_create_user_command(neutral, action, opts)
		end
	end
end

function M.setup(api)
	if state.setup_done or vim.g.vscode then
		return
	end
	state.setup_done = true
	spinner.define_signs()
	command("AgentBackend", require("agents.selection").command, {
		nargs = "?",
		complete = function()
			return require("agents.selection").ids
		end,
		desc = "Select the project agent backend (OpenCode or Pi)",
	})
	vim.keymap.set("n", "<leader>aB", require("agents.selection").command, { desc = "Agents: select backend" })
	for name, action in pairs({
		AgentChat = api.toggle,
		AgentChatNew = api.new_chat,
		AgentSessions = api.toggle_chat_buffers,
		AgentJobs = api.toggle_jobs,
		AgentHealth = api.health,
	}) do
		command(name, action, { desc = "Agent workflow" })
	end

	command("OpenCodeChat", api.toggle, { desc = "Toggle the Agent chat" })
	command("OpenCodeChatBuffers", api.toggle_chat_buffers, { desc = "Toggle Agent chat buffers" })
	command("OpenCodeChatNew", api.new_chat, { desc = "Start a new Agent chat" })
	command("OpenCodeChatAttach", api.attach_chat, { desc = "Open the agent attachment dashboard" })
	command("AgentDashboard", api.attach_chat, { desc = "Open the agent attachment dashboard" })
	command("OpenCodeChatResync", api.resync_chat_command, { desc = "Resync the Agent chat", nargs = "?" })
	command("OpenCodeQuery", api.query, { desc = "Ask a read-only question without editor context" })
	command("OpenCodeQueryFile", api.query_file, { desc = "Ask a read-only question about the current file" })
	command(
		"OpenCodeQueryFileDiagnostics",
		api.query_file_diagnostics,
		{ desc = "Ask a read-only question using current file diagnostics" }
	)
	command(
		"OpenCodeQueryLineDiagnostics",
		api.query_line_diagnostics,
		{ desc = "Ask a read-only question using current line diagnostics" }
	)
	command(
		"OpenCodeQuerySelection",
		api.query_selection,
		{ desc = "Ask a read-only question about the selected text", range = true }
	)
	command(
		"OpenCodeQuerySelectionDiagnostics",
		api.query_selection_diagnostics,
		{ desc = "Ask a read-only question using selected text and its diagnostics", range = true }
	)
	command(
		"OpenCodePrepareCommit",
		api.prepare_commit,
		{ desc = "Stage all changes and prepare a commit message with Agent" }
	)
	command(
		"OpenCodeCommit",
		api.commit,
		{ desc = "Commit prepared changes or stage all and generate a commit message" }
	)
	command(
		"OpenCodeReviewCommit",
		api.review_commit,
		{ desc = "Review the commit message prepared by AgentPrepareCommit" }
	)
	command("OpenCodeEditFile", api.edit_file, { desc = "Apply changes to the current file with Agent" })
	command(
		"OpenCodeEditSelection",
		api.edit_selection,
		{ desc = "Apply changes to the selected text with Agent", range = true }
	)
	command("OpenCodeEphemeralModel", api.select_ephemeral_model, {
		complete = function()
			return { "edit", "query", "commit" }
		end,
		desc = "Select the ephemeral Agent model",
		nargs = "?",
	})
	command("OpenCodeHealth", api.health, { desc = "Check Agent integration health" })
	command("OpenCodeJobs", api.toggle_jobs, { desc = "Toggle Agent jobs" })
	command("OpenCodeJobsDelete", api.delete_job, { desc = "Delete an agent job", nargs = "?" })
	command("OpenCodeSendFile", api.send_file, { desc = "Send the current file to Agent" })
	command(
		"OpenCodeSendFileDiagnostics",
		api.send_file_diagnostics,
		{ desc = "Send the current file and its diagnostics to Agent" }
	)
	command("OpenCodeSendLine", api.send_line, { desc = "Send the current line to Agent" })
	command(
		"OpenCodeSendLineDiagnostics",
		api.send_line_diagnostics,
		{ desc = "Send the current line and its diagnostics to Agent" }
	)
	command("OpenCodeSendParagraph", api.send_paragraph, { desc = "Send the current paragraph to Agent" })
	command("OpenCodeSendSelection", api.send_selection, { desc = "Send the selected text to Agent", range = true })
	command(
		"OpenCodeSendSelectionDiagnostics",
		api.send_selection_diagnostics,
		{ desc = "Send selected text and its diagnostics to Agent", range = true }
	)

	vim.keymap.set("n", "<leader>aj", api.toggle_jobs, { desc = "Agent: toggle background jobs" })
	vim.keymap.set("n", "<leader>aa", api.toggle, { desc = "Agent: toggle the chat window" })
	vim.keymap.set("n", "<leader>ab", api.toggle_chat_buffers, { desc = "Agent: toggle chat buffers" })
	vim.keymap.set("n", "<leader>an", api.new_chat, { desc = "Agent: start a new chat" })
	vim.keymap.set("n", "<leader>aA", api.attach_chat, { desc = "Agents: attachment dashboard" })
	vim.keymap.set(
		"n",
		"<leader>ac",
		api.query_file,
		{ desc = "Agent: ask a read-only question about the current file" }
	)
	vim.keymap.set("n", "<leader>aq", api.query, { desc = "Agent: ask a read-only question without editor context" })
	vim.keymap.set("n", "<leader>aC", api.commit, { desc = "Agent: commit changes" })
	vim.keymap.set(
		"x",
		"<leader>ac",
		api.query_selection,
		{ desc = "Agent: ask a read-only question about selected text" }
	)
	vim.keymap.set("n", "<leader>ae", api.edit_file, { desc = "Agent: apply changes to the current file" })
	vim.keymap.set("x", "<leader>ae", api.edit_selection, { desc = "Agent: apply changes to selected text" })

	vim.keymap.set("n", "<leader>ad", api.send_file_diagnostics, { desc = "Agent: send file context and diagnostics" })
	vim.keymap.set(
		"x",
		"<leader>ad",
		api.send_selection_diagnostics,
		{ desc = "Agent: send selected text and diagnostics" }
	)
	vim.keymap.set(
		"n",
		"<leader>ar",
		api.query_file_diagnostics,
		{ desc = "Agent: ask a read-only question with file diagnostics" }
	)
	vim.keymap.set(
		"x",
		"<leader>ar",
		api.query_selection_diagnostics,
		{ desc = "Agent: ask a read-only question with selection diagnostics" }
	)

	vim.keymap.set("n", "<leader>ap", api.send_paragraph, { desc = "Agent: send the current paragraph" })

	vim.keymap.set("n", "<leader>as", api.send_file, { desc = "Agent: send the current file as context" })
	vim.keymap.set("x", "<leader>as", api.send_selection, { desc = "Agent: send selected text" })
	vim.keymap.set("n", "<leader>al", api.send_line, { desc = "Agent: send the current line" })

	vim.keymap.set("n", "<leader>aH", api.health, { desc = "Agent: check integration health" })
	vim.keymap.set("n", "<leader>am", api.select_ephemeral_model, { desc = "Agent: select the ephemeral model" })

	vim.api.nvim_create_autocmd("BufEnter", {
		group = vim.api.nvim_create_augroup("opencode-chat-targets", { clear = true }),
		callback = function(event)
			api.activate_buffer(event.buf)
		end,
	})
end

return M
