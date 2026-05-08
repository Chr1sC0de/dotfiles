local M = {}

local CODEX_BUF_NAME = "codex://chat"
local codex_buf = nil
local codex_job_id = nil
local previous_buf = nil
local setup_done = false

local function notify(message, level)
	level = level or vim.log.levels.INFO

	local ok, notify_fn = pcall(require, "notify")
	if ok then
		notify_fn(message, level, { title = "Codex" })
	else
		vim.notify(message, level, { title = "Codex" })
	end
end

local function is_valid_buffer(bufnr)
	return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

local function is_codex_buffer(bufnr)
	return is_valid_buffer(bufnr) and bufnr == codex_buf
end

local function is_codex_running()
	return codex_job_id ~= nil and vim.fn.jobwait({ codex_job_id }, 0)[1] == -1
end

local function remember_previous_buffer()
	local current = vim.api.nvim_get_current_buf()
	if is_valid_buffer(current) and not is_codex_buffer(current) then
		previous_buf = current
	end
end

local function find_fallback_buffer()
	local alternate = vim.fn.bufnr("#")
	if alternate > 0 and is_valid_buffer(alternate) and not is_codex_buffer(alternate) then
		return alternate
	end

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if bufnr ~= codex_buf and vim.bo[bufnr].buflisted and vim.api.nvim_buf_is_loaded(bufnr) then
			return bufnr
		end
	end

	return nil
end

local function switch_to_previous_buffer()
	if is_valid_buffer(previous_buf) and not is_codex_buffer(previous_buf) then
		vim.api.nvim_set_current_buf(previous_buf)
		return
	end

	local fallback = find_fallback_buffer()
	if fallback then
		vim.api.nvim_set_current_buf(fallback)
	end
end

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

local function start_codex()
	if vim.fn.executable("codex") ~= 1 then
		notify("codex executable was not found on PATH", vim.log.levels.ERROR)
		return false
	end

	if is_valid_buffer(codex_buf) then
		pcall(vim.api.nvim_buf_delete, codex_buf, { force = true })
	end

	remember_previous_buffer()
	vim.cmd("enew")

	local buf = vim.api.nvim_get_current_buf()
	codex_buf = buf

	vim.api.nvim_buf_set_name(buf, CODEX_BUF_NAME)
	vim.bo[buf].buflisted = true
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "codex"
	vim.b[buf].codex_chat = true
	vim.b[buf].codex_cwd = vim.fn.getcwd()

	local term_buf = buf
	codex_job_id = vim.fn.termopen({ "codex", "--cd", vim.fn.getcwd() }, {
		on_exit = function(job_id, code)
			if codex_job_id == job_id then
				codex_job_id = nil
			end

			vim.schedule(function()
				if is_valid_buffer(term_buf) then
					vim.b[term_buf].codex_exited = true
				end
				notify("Codex chat exited with code " .. code, code == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
			end)
		end,
	})

	vim.cmd("startinsert")
	return true
end

local function ensure_codex()
	if is_valid_buffer(codex_buf) and is_codex_running() then
		return true
	end

	return start_codex()
end

local function paste_to_codex(text)
	if not ensure_codex() or not is_codex_running() then
		return false
	end

	local payload = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	vim.api.nvim_chan_send(codex_job_id, "\027[200~" .. payload .. "\027[201~\r")
	return true
end

local function get_selected_text_from_marks()
	local mode = vim.fn.visualmode()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")

	local start_line = start_pos[2]
	local start_col = start_pos[3]
	local end_line = end_pos[2]
	local end_col = end_pos[3]

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

	if mode == "\022" then
		for i, line in ipairs(lines) do
			lines[i] = line:sub(start_col, end_col)
		end
		return table.concat(lines, "\n"), start_line, end_line
	end

	lines[#lines] = lines[#lines]:sub(1, end_col)
	lines[1] = lines[1]:sub(start_col)

	return table.concat(lines, "\n"), start_line, end_line
end

local function get_selected_text(opts)
	if opts and opts.range and opts.range > 0 then
		local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
		return table.concat(lines, "\n"), opts.line1, opts.line2
	end

	return get_selected_text_from_marks()
end

local function send_text_context(kind, text, start_line, end_line)
	local path, _, filetype, modified = buffer_file_context()
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

	if paste_to_codex(prompt) then
		notify("Sent " .. kind .. " to Codex: " .. path .. ":" .. start_line .. "-" .. end_line)
	end
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

function M.toggle()
	if is_codex_buffer(vim.api.nvim_get_current_buf()) then
		switch_to_previous_buffer()
		return
	end

	remember_previous_buffer()
	if ensure_codex() then
		vim.api.nvim_set_current_buf(codex_buf)
		vim.cmd("startinsert")
	end
end

function M.send_file()
	local path, line, filetype, modified = buffer_file_context()
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

	if paste_to_codex(prompt) then
		notify("Sent file context to Codex: " .. path)
	end
end

function M.send_selection(opts)
	local selected_text, start_line, end_line = get_selected_text(opts)

	if selected_text == "" then
		notify("No visual selection to send to Codex", vim.log.levels.WARN)
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
		notify("No paragraph under cursor to send to Codex", vim.log.levels.WARN)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	send_text_context("paragraph", table.concat(lines, "\n"), start_line, end_line)
end

function M.setup()
	if setup_done or vim.g.vscode then
		return
	end
	setup_done = true

	vim.api.nvim_create_user_command("CodexChat", M.toggle, {})
	vim.api.nvim_create_user_command("CodexSendFile", M.send_file, {})
	vim.api.nvim_create_user_command("CodexSendLine", M.send_line, {})
	vim.api.nvim_create_user_command("CodexSendParagraph", M.send_paragraph, {})
	vim.api.nvim_create_user_command("CodexSendSelection", M.send_selection, { range = true })

	vim.keymap.set("n", "<leader>aa", M.toggle, { desc = "Codex: toggle chat" })
	vim.keymap.set("n", "<leader>af", M.send_file, { desc = "Codex: send file context" })
	vim.keymap.set("n", "<leader>al", M.send_line, { desc = "Codex: send line" })
	vim.keymap.set("n", "<leader>ap", M.send_paragraph, { desc = "Codex: send paragraph" })
	vim.keymap.set("x", "<leader>as", M.send_selection, { desc = "Codex: send selection" })
end

return M
