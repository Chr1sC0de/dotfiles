local chat = require("codex.chat")
local chat_panel = require("codex.chat_panel")
local commands = require("codex.commands")
local context = require("codex.context")
local health = require("codex.health")
local jobs = require("codex.ephemeral.jobs")
local jobs_panel = require("codex.ephemeral.jobs_panel")
local model = require("codex.ephemeral.model")
local util = require("codex.util")

local M = {}

M.toggle = chat.toggle
M.new_chat = chat.new
M.paste = chat.paste
M.delete_chat_buffer = chat.delete_buffer
M.generate_chat_title = chat.generate_title
M.set_chat_title = chat.set_title
M.resync_chat = chat.resync
M.toggle_chat_buffers = chat_panel.toggle
M.send_file = context.send_file
M.send_selection = context.send_selection
M.send_line = context.send_line
M.send_paragraph = context.send_paragraph
M.send_file_diagnostics = context.send_file_diagnostics
M.send_line_diagnostics = context.send_line_diagnostics
M.send_selection_diagnostics = context.send_selection_diagnostics
M.command_file_diagnostics = context.command_file_diagnostics
M.command_line_diagnostics = context.command_line_diagnostics
M.command_selection_diagnostics = context.command_selection_diagnostics
M.command_file = context.command_file
M.command_selection = context.command_selection
M.edit_file = context.edit_file
M.edit_selection = context.edit_selection
M.health = health.report
M.toggle_jobs = jobs_panel.toggle
M.activate_buffer = chat.activate_buffer

function M.delete_job(opts)
	local id = opts and opts.args and opts.args ~= "" and opts.args or nil
	if id then
		jobs.delete_by_id(id)
		return
	end

	if jobs_panel.is_current_window() then
		jobs_panel.delete_selected()
		return
	end

	util.notify("Usage: CodexJobsDelete <id>", vim.log.levels.WARN)
end

function M.select_ephemeral_model(opts)
	local action = opts and util.trim_whitespace(opts.args) or ""
	if action == "" then
		model.select_target()
		return
	end

	model.select(action)
end

function M.resync_chat_command(opts)
	local id = opts and util.trim_whitespace(opts.args) or ""
	if id == "" then
		M.resync_chat()
		return
	end

	for _, session in ipairs(chat.list()) do
		if tostring(session.id) == id then
			M.resync_chat(session.bufnr)
			return
		end
	end

	util.notify("Codex chat #" .. id .. " not found", vim.log.levels.WARN)
end

function M.setup()
	commands.setup(M)
end

return M
