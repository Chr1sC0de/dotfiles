local selection = require("codex.context.selection")
local util = require("codex.util")

local M = {}

function M.build_prompt()
	return {
		kind = "prompt",
		path = "",
		modified = "no",
		spinner_buf = vim.api.nvim_get_current_buf(),
		spinner_line = vim.api.nvim_win_get_cursor(0)[1],
		context_lines = {},
	}
end

function M.build_file(opts)
	opts = opts or {}
	local _, line, filetype, modified = util.buffer_file_context()
	local source = util.buffer_source()
	local path = source.path
	local context_lines = {
		(source.file_path and "File: " or "Buffer: ") .. path,
		"Line: " .. line,
		"Filetype: " .. filetype,
		"Unsaved changes: " .. modified,
		"",
	}
	local snapshot_path = nil

	if not source.file_path then
		vim.list_extend(context_lines, util.buffer_reference_lines())
	elseif modified == "yes" and opts.include_modified_snapshot then
		snapshot_path = util.write_current_buffer_snapshot()
		if snapshot_path then
			vim.list_extend(context_lines, {
				"Unsaved buffer snapshot: " .. snapshot_path,
				"Read the snapshot file when you need the current unsaved buffer content.",
			})
		else
			table.insert(context_lines, "The buffer has unsaved changes, and no snapshot could be written.")
		end
	else
		table.insert(context_lines, "The file is available in the workspace. Read it from disk if needed.")
	end

	return {
		kind = source.file_path and "file" or "buffer",
		path = path,
		file_path = source.file_path,
		source_buf = source.source_buf,
		line = line,
		start_line = line,
		end_line = line,
		filetype = filetype,
		modified = modified,
		snapshot_path = snapshot_path,
		spinner_buf = vim.api.nvim_get_current_buf(),
		spinner_line = line,
		context_lines = context_lines,
	}
end

function M.build_selection(opts)
	local _, _, filetype, modified = util.buffer_file_context()
	local source = util.buffer_source()
	local path = source.path
	local selected_text, start_line, end_line = selection.get_text(opts)

	if selected_text == "" then
		util.notify("No visual selection for ephemeral Codex job", vim.log.levels.WARN)
		return nil
	end

	return {
		kind = "selection",
		path = path,
		file_path = source.file_path,
		source_buf = source.source_buf,
		start_line = start_line,
		end_line = end_line,
		filetype = filetype,
		modified = modified,
		spinner_buf = vim.api.nvim_get_current_buf(),
		spinner_line = start_line,
		context_lines = {
			(source.file_path and "File: " or "Buffer: ") .. path,
			"Lines: " .. start_line .. "-" .. end_line,
			"Filetype: " .. filetype,
			"Unsaved changes: " .. modified,
			"",
			source.file_path and "Selected file text:"
				or "Selected non-file buffer text (read-only reference context):",
			"```" .. filetype,
			selected_text,
			"```",
		},
	}
end

return M
