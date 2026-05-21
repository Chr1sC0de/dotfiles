local selection = require("codex.context.selection")
local util = require("codex.util")

local M = {}

function M.build_file()
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

function M.build_selection(opts)
	local path, _, filetype, modified = util.buffer_file_context()
	local selected_text, start_line, end_line = selection.get_text(opts)

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

return M
