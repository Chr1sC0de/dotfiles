local constants = require("codex.constants")
local util = require("codex.util")

local M = {}

local severity_labels = {
	[vim.diagnostic.severity.ERROR] = "ERROR",
	[vim.diagnostic.severity.WARN] = "WARN",
	[vim.diagnostic.severity.INFO] = "INFO",
	[vim.diagnostic.severity.HINT] = "HINT",
}

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

function M.scope_label(kind, start_line, end_line)
	if kind == "file" then
		return "current file"
	end
	if kind == "line" then
		return "current line " .. start_line
	end

	return "highlighted lines " .. start_line .. "-" .. end_line
end

local function build_context_lines(kind, diagnostics, start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()
	local path, cursor_line, filetype, modified = util.buffer_file_context()
	local prompt_lines = {
		"Diagnostic scope: " .. M.scope_label(kind, start_line, end_line),
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

function M.build_prompt(kind, context_lines, start_line, end_line)
	local prompt_lines = {
		"Use these "
			.. M.scope_label(kind, start_line, end_line)
			.. " diagnostics as context for the current Codex chat.",
		"",
	}

	vim.list_extend(prompt_lines, context_lines)
	table.insert(prompt_lines, "")
	table.insert(prompt_lines, "Treat this diagnostics message as read-only context, don't make any edits")

	return table.concat(prompt_lines, "\n")
end

function M.build_target(kind, start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()
	local diagnostics = get_diagnostics(bufnr, start_line, end_line)

	if #diagnostics == 0 then
		util.notify("No diagnostics found for " .. M.scope_label(kind, start_line, end_line), vim.log.levels.WARN)
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
		context_lines = build_context_lines(kind, diagnostics, start_line, end_line),
	}
end

return M
