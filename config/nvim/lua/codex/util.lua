local state = require("codex.state")

local M = {}

function M.notify(message, level)
	level = level or vim.log.levels.INFO

	local ok, notify_fn = pcall(require, "notify")
	if ok then
		notify_fn(message, level, { title = "Codex" })
	else
		vim.notify(message, level, { title = "Codex" })
	end
end

function M.is_valid_buffer(bufnr)
	return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

function M.is_valid_window(winid)
	return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

function M.is_codex_buffer(bufnr)
	return M.is_valid_buffer(bufnr) and (vim.b[bufnr].codex_chat == true or state.codex_sessions[bufnr] ~= nil)
end

function M.repo_relative_path(path)
	if path == "" then
		return "[No Name]"
	end

	return vim.fn.fnamemodify(path, ":.")
end

function M.join_path(parent, child)
	if vim.fs and vim.fs.joinpath then
		return vim.fs.joinpath(parent, child)
	end

	local last_char = parent:sub(-1)
	if last_char == "/" or last_char == "\\" then
		return parent .. child
	end

	return parent .. package.config:sub(1, 1) .. child
end

function M.buffer_file_context()
	local path = M.repo_relative_path(vim.api.nvim_buf_get_name(0))
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local filetype = vim.bo.filetype ~= "" and vim.bo.filetype or "unknown"
	local modified = vim.bo.modified and "yes" or "no"

	return path, line, filetype, modified
end

function M.trim_whitespace(value)
	if value == nil then
		return ""
	end

	return tostring(value):match("^%s*(.-)%s*$")
end

function M.trim_display(value, width)
	value = tostring(value or "")
	if #value <= width then
		return value
	end

	return value:sub(1, math.max(width - 3, 1)) .. "..."
end

function M.job_instruction_display(job)
	local instruction = job and job.instruction or ""
	instruction = instruction:gsub("%s+", " ")
	return M.trim_whitespace(instruction)
end

return M
