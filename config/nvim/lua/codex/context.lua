local chat = require("codex.chat")
local diagnostics = require("codex.context.diagnostics")
local jobs = require("codex.ephemeral.jobs")
local oil = require("codex.context.oil")
local selection = require("codex.context.selection")
local targets = require("codex.context.targets")
local util = require("codex.util")

local M = {}

function M.build_file_target(opts)
	return targets.build_file(opts)
end

function M.build_selection_target(opts)
	return targets.build_selection(opts)
end

local function send_text_context(kind, text, start_line, end_line)
	local path, _, filetype, modified = util.buffer_file_context()
	local prompt = table.concat({
		"Use this " .. kind .. " as context for the current Codex chat.",
		"",
		"File: " .. path,
		"Lines: " .. start_line .. "-" .. end_line,
		"Filetype: " .. filetype,
		"Unsaved changes: " .. modified,
		"",
		"```" .. filetype,
		text,
		"```",
	}, "\n")

	if chat.paste(prompt) then
		util.notify("Sent " .. kind .. " to Codex: " .. path .. ":" .. start_line .. "-" .. end_line)
	end
end

local function send_diagnostics(kind, start_line, end_line)
	local target = diagnostics.build_target(kind, start_line, end_line)
	if not target then
		return
	end

	if chat.paste(diagnostics.build_prompt(kind, target.context_lines, start_line, end_line)) then
		util.notify(
			"Sent " .. diagnostics.scope_label(kind, start_line, end_line) .. " diagnostics to Codex: " .. target.path
		)
	end
end

local function command_diagnostics(kind, start_line, end_line)
	jobs.prompt_and_run("command", diagnostics.build_target(kind, start_line, end_line), "Codex diagnostic question: ")
end

function M.send_file()
	local path, line, filetype, modified = util.buffer_file_context()
	local prompt_lines = {
		"Use this file as context for the current Codex chat.",
		"",
		"File: " .. path,
		"Line: " .. line,
		"Filetype: " .. filetype,
		"Unsaved changes: " .. modified,
		"",
	}

	if modified == "yes" then
		local snapshot_path = util.write_current_buffer_snapshot()
		if snapshot_path then
			vim.list_extend(prompt_lines, {
				"Unsaved buffer snapshot: " .. snapshot_path,
				"Read the snapshot file when you need the current unsaved buffer content.",
			})
		else
			table.insert(prompt_lines, "The buffer has unsaved changes, and no snapshot could be written.")
		end
	else
		table.insert(prompt_lines, "Open/read this file as needed before making suggestions.")
	end

	local prompt = table.concat(prompt_lines, "\n")

	if chat.paste(prompt) then
		util.notify("Sent file context to Codex: " .. path)
	end
end

function M.send_selection(opts)
	local selected_text, start_line, end_line = selection.get_text(opts)

	if selected_text == "" then
		util.notify("No visual selection to send to Codex", vim.log.levels.WARN)
		return
	end

	if oil.send_selection_context(selected_text, start_line, end_line) then
		return
	end

	send_text_context("selection", selected_text, start_line, end_line)
end

function M.send_line()
	local line_number = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(0, line_number - 1, line_number, false)[1] or ""

	send_text_context("line", line, line_number, line_number)
end

function M.send_paragraph()
	local start_line, end_line = selection.current_paragraph_range()
	if not start_line or not end_line then
		util.notify("No paragraph under cursor to send to Codex", vim.log.levels.WARN)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	send_text_context("paragraph", table.concat(lines, "\n"), start_line, end_line)
end

function M.send_file_diagnostics()
	send_diagnostics("file")
end

function M.send_line_diagnostics()
	local line_number = vim.api.nvim_win_get_cursor(0)[1]
	send_diagnostics("line", line_number, line_number)
end

function M.send_selection_diagnostics(opts)
	local _, start_line, end_line = selection.get_text(opts)

	if not start_line or not end_line or start_line == 0 or end_line == 0 then
		util.notify("No highlighted lines to send diagnostics for", vim.log.levels.WARN)
		return
	end

	send_diagnostics("selection", start_line, end_line)
end

function M.command_file_diagnostics()
	command_diagnostics("file")
end

function M.command_line_diagnostics()
	local line_number = vim.api.nvim_win_get_cursor(0)[1]
	command_diagnostics("line", line_number, line_number)
end

function M.command_selection_diagnostics(opts)
	local _, start_line, end_line = selection.get_text(opts)

	if not start_line or not end_line or start_line == 0 or end_line == 0 then
		util.notify("No highlighted lines to command diagnostics over", vim.log.levels.WARN)
		return
	end

	command_diagnostics("selection", start_line, end_line)
end

function M.command_file()
	jobs.prompt_and_run("command", M.build_file_target({ include_modified_snapshot = true }))
end

function M.command_selection(opts)
	jobs.prompt_and_run("command", M.build_selection_target(opts))
end

function M.edit_file()
	jobs.prompt_and_run("edit", M.build_file_target())
end

function M.edit_selection(opts)
	jobs.prompt_and_run("edit", M.build_selection_target(opts))
end

return M
