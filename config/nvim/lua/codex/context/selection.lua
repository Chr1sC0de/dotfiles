local constants = require("codex.constants")

local M = {}

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

function M.get_text(opts)
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

local function line_is_blank(line)
	return line:match("^%s*$") ~= nil
end

function M.current_paragraph_range()
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

return M
