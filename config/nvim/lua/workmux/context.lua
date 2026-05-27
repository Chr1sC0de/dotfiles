local selection = require("codex.context.selection")

local M = {}

local function repo_relative_path(path)
	if path == "" then
		return "[No Name]"
	end

	return vim.fn.fnamemodify(path, ":.")
end

local function buffer_file_context()
	local path = repo_relative_path(vim.api.nvim_buf_get_name(0))
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local filetype = vim.bo.filetype ~= "" and vim.bo.filetype or "unknown"
	local modified = vim.bo.modified and "yes" or "no"

	return path, line, filetype, modified
end

function M.build_prompt(prompt, target)
	local lines = {
		"Use this " .. target.kind .. " as context for the Workmux agent task.",
		"",
		"Task:",
		prompt,
		"",
	}

	vim.list_extend(lines, target.context_lines)

	return table.concat(lines, "\n")
end

function M.build_file_target()
	local path, line, filetype, modified = buffer_file_context()

	return {
		kind = "file",
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

function M.build_file_prompt(prompt)
	return M.build_prompt(prompt, M.build_file_target())
end

function M.build_selection_target(opts)
	local path, _, filetype, modified = buffer_file_context()
	local selected_text, start_line, end_line = selection.get_text(opts)

	if selected_text == "" then
		return nil
	end

	return {
		kind = "selection",
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

function M.build_selection_prompt(prompt, opts)
	local target = M.build_selection_target(opts)
	if target == nil then
		return nil
	end

	return M.build_prompt(prompt, target)
end

return M
