local chat = require("codex.chat")
local constants = require("codex.constants")
local jobs = require("codex.ephemeral.jobs")
local util = require("codex.util")

local M = {}

local severity_labels = {
	[vim.diagnostic.severity.ERROR] = "ERROR",
	[vim.diagnostic.severity.WARN] = "WARN",
	[vim.diagnostic.severity.INFO] = "INFO",
	[vim.diagnostic.severity.HINT] = "HINT",
}

local function get_selected_text_from_positions(mode, start_pos, end_pos)
	local start_line = start_pos[2]
	local start_col = start_pos[3]
	local end_line = end_pos[2]
	local end_col = end_pos[3]

	if start_line == 0 or end_line == 0 then
		return "", start_line, end_line
	end

	if start_line > end_line or (start_line == end_line and start_col > end_col) then
		start_line, end_line = end_line, start_line
		start_col, end_col = end_col, start_col
	end

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	if #lines == 0 then
		return "", start_line, end_line
	end

	if mode == "V" then
		return table.concat(lines, "\n"), start_line, end_line
	end

	if mode == constants.VISUAL_BLOCK_MODE then
		local col_start = math.min(start_col, end_col)
		local col_end = math.max(start_col, end_col)

		for i, line in ipairs(lines) do
			lines[i] = line:sub(col_start, col_end)
		end
		return table.concat(lines, "\n"), start_line, end_line
	end

	lines[#lines] = lines[#lines]:sub(1, end_col)
	lines[1] = lines[1]:sub(start_col)

	return table.concat(lines, "\n"), start_line, end_line
end

local function get_selected_text_from_live_visual()
	local mode = vim.fn.mode()
	if mode ~= "v" and mode ~= "V" and mode ~= constants.VISUAL_BLOCK_MODE then
		return nil, nil, nil
	end

	return get_selected_text_from_positions(mode, vim.fn.getpos("v"), vim.fn.getcurpos())
end

local function get_selected_text_from_marks()
	return get_selected_text_from_positions(vim.fn.visualmode(), vim.fn.getpos("'<"), vim.fn.getpos("'>"))
end

local function get_selected_text(opts)
	if opts and opts.range and opts.range > 0 then
		local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
		return table.concat(lines, "\n"), opts.line1, opts.line2
	end

	local selected_text, start_line, end_line = get_selected_text_from_live_visual()
	if selected_text ~= nil then
		return selected_text, start_line, end_line
	end

	return get_selected_text_from_marks()
end

function M.build_file_target()
	local path, line, filetype, modified = util.buffer_file_context()

	return {
		kind = "file",
		path = path,
		line = line,
		start_line = line,
		end_line = line,
		filetype = filetype,
		modified = modified,
		spinner_buf = vim.api.nvim_get_current_buf(),
		spinner_line = line,
		context_lines = {
			"File: " .. path,
			"Line: " .. line,
			"Filetype: " .. filetype,
			"Unsaved changes: " .. modified,
			"",
			"The file is available in the workspace. Read it from disk if needed.",
		},
	}
end

function M.build_selection_target(opts)
	local path, _, filetype, modified = util.buffer_file_context()
	local selected_text, start_line, end_line = get_selected_text(opts)

	if selected_text == "" then
		util.notify("No visual selection for ephemeral Codex job", vim.log.levels.WARN)
		return nil
	end

	return {
		kind = "selection",
		path = path,
		start_line = start_line,
		end_line = end_line,
		filetype = filetype,
		modified = modified,
		spinner_buf = vim.api.nvim_get_current_buf(),
		spinner_line = start_line,
		context_lines = {
			"File: " .. path,
			"Lines: " .. start_line .. "-" .. end_line,
			"Filetype: " .. filetype,
			"Unsaved changes: " .. modified,
			"",
			"```" .. filetype,
			selected_text,
			"```",
		},
	}
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

local function diagnostic_severity_label(diagnostic)
	return severity_labels[diagnostic.severity] or tostring(diagnostic.severity or "UNKNOWN")
end

local function diagnostic_code(diagnostic)
	if diagnostic.code == nil or diagnostic.code == "" then
		return nil
	end

	return tostring(diagnostic.code)
end

local function diagnostic_range(diagnostic)
	local start_line = (diagnostic.lnum or 0) + 1
	local end_line = (diagnostic.end_lnum or diagnostic.lnum or 0) + 1

	if end_line < start_line then
		end_line = start_line
	end

	return start_line, end_line
end

local function diagnostic_intersects_range(diagnostic, start_line, end_line)
	if not start_line or not end_line then
		return true
	end

	local diagnostic_start, diagnostic_end = diagnostic_range(diagnostic)
	return diagnostic_start <= end_line and diagnostic_end >= start_line
end

local function diagnostic_sort_key(diagnostic)
	return diagnostic.lnum or 0, diagnostic.col or 0, diagnostic.severity or 999, diagnostic.message or ""
end

local function compare_diagnostics(left, right)
	local left_line, left_col, left_severity, left_message = diagnostic_sort_key(left)
	local right_line, right_col, right_severity, right_message = diagnostic_sort_key(right)

	if left_line ~= right_line then
		return left_line < right_line
	end
	if left_col ~= right_col then
		return left_col < right_col
	end
	if left_severity ~= right_severity then
		return left_severity < right_severity
	end

	return left_message < right_message
end

local function get_diagnostics(bufnr, start_line, end_line)
	local diagnostics = {}

	for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
		if
			diagnostic.namespace ~= constants.EPHEMERAL_DIAGNOSTIC_NAMESPACE
			and diagnostic_intersects_range(diagnostic, start_line, end_line)
		then
			table.insert(diagnostics, diagnostic)
		end
	end

	table.sort(diagnostics, compare_diagnostics)
	return diagnostics
end

local function diagnostic_position(diagnostic)
	local start_line, end_line = diagnostic_range(diagnostic)
	local start_col = (diagnostic.col or 0) + 1
	local end_col = diagnostic.end_col and diagnostic.end_col + 1 or nil

	if start_line == end_line then
		if end_col and end_col ~= start_col then
			return start_line .. ":" .. start_col .. "-" .. end_col
		end

		return start_line .. ":" .. start_col
	end

	local position = start_line .. ":" .. start_col .. "-" .. end_line
	if end_col then
		position = position .. ":" .. end_col
	end
	return position
end

local function indent_multiline(value, prefix)
	return tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\n", "\n" .. prefix)
end

local function diagnostic_source_display(diagnostic)
	local source = diagnostic.source
	local code = diagnostic_code(diagnostic)

	if source and source ~= "" and code then
		return source .. "/" .. code
	end
	if source and source ~= "" then
		return source
	end
	if code then
		return code
	end

	local namespace = diagnostic.namespace and vim.diagnostic.get_namespaces()[diagnostic.namespace]
	return namespace and namespace.name or "unknown"
end

local function diagnostic_source_line(bufnr, diagnostic)
	local lnum = diagnostic.lnum or 0
	return vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
end

local function diagnostic_scope_label(kind, start_line, end_line)
	if kind == "file" then
		return "current file"
	end
	if kind == "line" then
		return "current line " .. start_line
	end

	return "highlighted lines " .. start_line .. "-" .. end_line
end

local function build_diagnostics_context_lines(kind, diagnostics, start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()
	local path, cursor_line, filetype, modified = util.buffer_file_context()
	local prompt_lines = {
		"Diagnostic scope: " .. diagnostic_scope_label(kind, start_line, end_line),
		"File: " .. path,
		"Line: " .. cursor_line,
		"Filetype: " .. filetype,
		"Unsaved changes: " .. modified,
	}

	if start_line and end_line then
		table.insert(prompt_lines, "Diagnostic lines: " .. start_line .. "-" .. end_line)
	end

	vim.list_extend(prompt_lines, {
		"",
		"Diagnostics:",
	})

	for index, diagnostic in ipairs(diagnostics) do
		table.insert(
			prompt_lines,
			string.format(
				"%d. [%s] %s at %s",
				index,
				diagnostic_severity_label(diagnostic),
				diagnostic_source_display(diagnostic),
				diagnostic_position(diagnostic)
			)
		)
		table.insert(prompt_lines, "   Message: " .. indent_multiline(diagnostic.message, "   "))
		table.insert(prompt_lines, "   Source line: " .. diagnostic_source_line(bufnr, diagnostic))
	end

	return prompt_lines
end

local function build_diagnostics_prompt(kind, context_lines, start_line, end_line)
	local prompt_lines = {
		"Use these "
			.. diagnostic_scope_label(kind, start_line, end_line)
			.. " diagnostics as context for the current Codex chat.",
		"",
	}

	vim.list_extend(prompt_lines, context_lines)
	table.insert(prompt_lines, "")
	table.insert(prompt_lines, "Treat this diagnostics message as read-only context, don't make any edits")

	return table.concat(prompt_lines, "\n")
end

local function build_diagnostics_target(kind, start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()
	local diagnostics = get_diagnostics(bufnr, start_line, end_line)

	if #diagnostics == 0 then
		util.notify(
			"No diagnostics found for " .. diagnostic_scope_label(kind, start_line, end_line),
			vim.log.levels.WARN
		)
		return
	end

	local path, cursor_line, filetype, modified = util.buffer_file_context()
	local target_start_line = start_line or 1
	local target_end_line = end_line or vim.api.nvim_buf_line_count(bufnr)

	return {
		kind = "diagnostics",
		path = path,
		start_line = target_start_line,
		end_line = target_end_line,
		filetype = filetype,
		modified = modified,
		spinner_buf = bufnr,
		spinner_line = start_line or cursor_line,
		context_lines = build_diagnostics_context_lines(kind, diagnostics, start_line, end_line),
	}
end

local function send_diagnostics(kind, start_line, end_line)
	local target = build_diagnostics_target(kind, start_line, end_line)
	if not target then
		return
	end

	if chat.paste(build_diagnostics_prompt(kind, target.context_lines, start_line, end_line)) then
		util.notify(
			"Sent " .. diagnostic_scope_label(kind, start_line, end_line) .. " diagnostics to Codex: " .. target.path
		)
	end
end

local function command_diagnostics(kind, start_line, end_line)
	jobs.prompt_and_run("command", build_diagnostics_target(kind, start_line, end_line), "Codex diagnostic question: ")
end

local function build_oil_selection_entries(oil, bufnr, directory, start_line, end_line)
	local entries = {}
	local seen_paths = {}

	for line = start_line, end_line do
		local entry = oil.get_entry_on_line(bufnr, line)
		local name = entry and util.trim_whitespace(entry.parsed_name or entry.name)

		if name and name ~= "" then
			local path = util.join_path(directory, name)
			if not seen_paths[path] then
				seen_paths[path] = true
				table.insert(entries, {
					path = util.repo_relative_path(path),
					type = entry.type or "unknown",
				})
			end
		end
	end

	return entries
end

local function send_oil_selection_context(text, start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].filetype ~= "oil" then
		return false
	end

	local ok, oil = pcall(require, "oil")
	if not ok then
		return false
	end

	local directory = oil.get_current_dir(bufnr)
	if not directory then
		return false
	end

	local entries = build_oil_selection_entries(oil, bufnr, directory, start_line, end_line)
	if #entries == 0 then
		return false
	end

	local entry_lines = {}
	for _, entry in ipairs(entries) do
		table.insert(entry_lines, "- " .. entry.path .. " [" .. entry.type .. "]")
	end

	local prompt_lines = {
		"Use this Oil directory selection as context for the current Codex chat.",
		"",
		"Directory: " .. util.repo_relative_path(directory),
		"Lines: " .. start_line .. "-" .. end_line,
		"Filetype: oil",
		"Unsaved Oil changes: " .. (vim.bo[bufnr].modified and "yes" or "no"),
		"",
		"Selected filesystem entries:",
	}
	vim.list_extend(prompt_lines, entry_lines)
	vim.list_extend(prompt_lines, {
		"",
		"These entries came from an Oil directory buffer. Read files or directories from disk if needed.",
		"",
		"Raw Oil selection:",
		"```oil",
		text,
		"```",
	})

	if chat.paste(table.concat(prompt_lines, "\n")) then
		util.notify(
			"Sent Oil selection to Codex: "
				.. util.repo_relative_path(directory)
				.. ":"
				.. start_line
				.. "-"
				.. end_line
		)
	end

	return true
end

local function line_is_blank(line)
	return line:match("^%s*$") ~= nil
end

local function current_paragraph_range()
	local line_count = vim.api.nvim_buf_line_count(0)
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local current_line = vim.api.nvim_buf_get_lines(0, cursor_line - 1, cursor_line, false)[1] or ""

	if line_is_blank(current_line) then
		return nil, nil
	end

	local start_line = cursor_line
	while start_line > 1 do
		local line = vim.api.nvim_buf_get_lines(0, start_line - 2, start_line - 1, false)[1] or ""
		if line_is_blank(line) then
			break
		end
		start_line = start_line - 1
	end

	local end_line = cursor_line
	while end_line < line_count do
		local line = vim.api.nvim_buf_get_lines(0, end_line, end_line + 1, false)[1] or ""
		if line_is_blank(line) then
			break
		end
		end_line = end_line + 1
	end

	return start_line, end_line
end

function M.send_file()
	local path, line, filetype, modified = util.buffer_file_context()
	local prompt = table.concat({
		"Use this file as context for the current Codex chat.",
		"",
		"File: " .. path,
		"Line: " .. line,
		"Filetype: " .. filetype,
		"Unsaved changes: " .. modified,
		"",
		"Open/read this file as needed before making suggestions.",
	}, "\n")

	if chat.paste(prompt) then
		util.notify("Sent file context to Codex: " .. path)
	end
end

function M.send_selection(opts)
	local selected_text, start_line, end_line = get_selected_text(opts)

	if selected_text == "" then
		util.notify("No visual selection to send to Codex", vim.log.levels.WARN)
		return
	end

	if send_oil_selection_context(selected_text, start_line, end_line) then
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
	local start_line, end_line = current_paragraph_range()
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
	local _, start_line, end_line = get_selected_text(opts)

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
	local _, start_line, end_line = get_selected_text(opts)

	if not start_line or not end_line or start_line == 0 or end_line == 0 then
		util.notify("No highlighted lines to command diagnostics over", vim.log.levels.WARN)
		return
	end

	command_diagnostics("selection", start_line, end_line)
end

function M.command_file()
	jobs.prompt_and_run("command", M.build_file_target())
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
