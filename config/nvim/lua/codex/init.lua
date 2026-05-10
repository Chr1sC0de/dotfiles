local chat = require("codex.chat")
local commands = require("codex.commands")
local context = require("codex.context")
local jobs = require("codex.ephemeral.jobs")
local jobs_panel = require("codex.ephemeral.jobs_panel")
local model = require("codex.ephemeral.model")
local util = require("codex.util")

local M = {}

M.toggle = chat.toggle
M.send_file = context.send_file
M.send_selection = context.send_selection
M.send_line = context.send_line
M.send_paragraph = context.send_paragraph
M.command_file = context.command_file
M.command_selection = context.command_selection
M.edit_file = context.edit_file
M.edit_selection = context.edit_selection
M.toggle_jobs = jobs_panel.toggle

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

function M.setup()
	commands.setup(M)
end

return M
