local M = {}

local CODEX_BUF_NAME = "codex://chat"
local EPHEMERAL_RESULT_SUBDIR = "codex/ephemeral"
local EPHEMERAL_DIAGNOSTIC_NAMESPACE = vim.api.nvim_create_namespace("codex-ephemeral")
local EPHEMERAL_SIGN_GROUP = "codex-ephemeral"
local EPHEMERAL_SPINNER_SIGNS = {
	{ name = "CodexEphemeralSpinner1", text = "|" },
	{ name = "CodexEphemeralSpinner2", text = "/" },
	{ name = "CodexEphemeralSpinner3", text = "-" },
	{ name = "CodexEphemeralSpinner4", text = "\\" },
}
local codex_buf = nil
local codex_job_id = nil
local previous_buf = nil
local active_ephemeral_diagnostics = {}
local next_ephemeral_diagnostic_id = 1
local next_ephemeral_result_id = 1
local next_ephemeral_sign_id = 1
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

local function get_ephemeral_result_dir()
	local state_dir = vim.fn.stdpath("state")
	local result_dir = state_dir .. "/" .. EPHEMERAL_RESULT_SUBDIR
	local ok, created = pcall(vim.fn.mkdir, result_dir, "p")

	if (ok and created == 1) or vim.fn.isdirectory(result_dir) == 1 then
		return result_dir
	end

	return vim.fn.fnamemodify(vim.fn.tempname(), ":h")
end

local function next_ephemeral_result_path()
	local id = next_ephemeral_result_id
	next_ephemeral_result_id = next_ephemeral_result_id + 1

	return string.format(
		"%s/codex-ephemeral-%s-%03d.md",
		get_ephemeral_result_dir(),
		os.date("%Y%m%d-%H%M%S"),
		id
	)
end

local function open_result_file(lines)
	local path = next_ephemeral_result_path()
	local ok = vim.fn.writefile(lines, path)

	if ok ~= 0 then
		notify("Failed to write ephemeral Codex result: " .. path, vim.log.levels.ERROR)
		return nil
	end

	vim.cmd("botright split")
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	vim.bo.filetype = "markdown"

	return path
end

local function define_ephemeral_signs()
	for _, sign in ipairs(EPHEMERAL_SPINNER_SIGNS) do
		vim.fn.sign_define(sign.name, { text = sign.text, texthl = "DiagnosticInfo" })
	end
end

local function refresh_ephemeral_diagnostics(bufnr)
	if not is_valid_buffer(bufnr) then
		return
	end

	local diagnostics = {}
	for _, record in pairs(active_ephemeral_diagnostics) do
		if record.bufnr == bufnr then
			table.insert(diagnostics, record.diagnostic)
		end
	end

	vim.diagnostic.set(EPHEMERAL_DIAGNOSTIC_NAMESPACE, bufnr, diagnostics, {})
end

local function start_ephemeral_diagnostic(action, target)
	local bufnr = target.spinner_buf
	if not is_valid_buffer(bufnr) then
		return function() end
	end

	local id = next_ephemeral_diagnostic_id
	next_ephemeral_diagnostic_id = next_ephemeral_diagnostic_id + 1
	active_ephemeral_diagnostics[id] = {
		bufnr = bufnr,
		diagnostic = {
			lnum = math.max(target.spinner_line - 1, 0),
			col = 0,
			severity = vim.diagnostic.severity.INFO,
			source = "codex",
			message = "Codex " .. action .. " running over " .. target.kind,
		},
	}
	refresh_ephemeral_diagnostics(bufnr)

	return function()
		active_ephemeral_diagnostics[id] = nil
		refresh_ephemeral_diagnostics(bufnr)
	end
end

local function start_ephemeral_spinner(bufnr, line)
	local sign_id = next_ephemeral_sign_id
	next_ephemeral_sign_id = next_ephemeral_sign_id + 1

	local timer = vim.uv.new_timer()
	local frame = 1
	local running = true

	local function place_sign()
		if not running or not is_valid_buffer(bufnr) then
			return
		end

		local sign = EPHEMERAL_SPINNER_SIGNS[frame]
		vim.fn.sign_place(sign_id, EPHEMERAL_SIGN_GROUP, sign.name, bufnr, {
			lnum = math.max(line, 1),
			priority = 30,
		})
		frame = frame % #EPHEMERAL_SPINNER_SIGNS + 1
	end

	place_sign()
	timer:start(120, 120, function()
		vim.schedule(place_sign)
	end)

	return function()
		running = false

		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end

		if is_valid_buffer(bufnr) then
			vim.fn.sign_unplace(EPHEMERAL_SIGN_GROUP, { buffer = bufnr, id = sign_id })
		end
	end
end

local function build_file_target()
	local path, line, filetype, modified = buffer_file_context()

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

local function build_selection_target(opts)
	local path, _, filetype, modified = buffer_file_context()
	local selected_text, start_line, end_line = get_selected_text(opts)

	if selected_text == "" then
		notify("No visual selection for ephemeral Codex job", vim.log.levels.WARN)
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

local function build_ephemeral_prompt(action, instruction, target)
	local mode_description
	if action == "edit" then
		mode_description = "Apply the user's requested edits if appropriate. Keep changes scoped to the supplied context."
	else
		mode_description = "Answer the user's instruction using the supplied context. Do not modify files."
	end

	local lines = {
		"You are running as an ephemeral Codex job from Neovim.",
		mode_description,
		"",
		"Instruction:",
		instruction,
		"",
		"Target: " .. target.kind,
	}

	vim.list_extend(lines, target.context_lines)

	return table.concat(lines, "\n")
end

local function make_result_lines(action, instruction, target, exit_code, stdout_lines, stderr_lines)
	local lines = {
		"# Codex Ephemeral Result",
		"",
		"- Action: " .. action,
		"- Target: " .. target.kind,
		"- Exit code: " .. exit_code,
		"- File: " .. target.path,
		"- Lines: " .. target.start_line .. "-" .. target.end_line,
		"",
		"## Instruction",
		"",
		instruction,
		"",
		"## Stdout",
		"",
		"```",
	}

	vim.list_extend(lines, stdout_lines)
	vim.list_extend(lines, {
		"```",
		"",
		"## Stderr",
		"",
		"```",
	})
	vim.list_extend(lines, stderr_lines)
	vim.list_extend(lines, { "```" })

	return lines
end

local function run_ephemeral(action, target, instruction)
	if instruction == nil or instruction:match("^%s*$") then
		return
	end

	if vim.fn.executable("codex") ~= 1 then
		notify("codex executable was not found on PATH", vim.log.levels.ERROR)
		return
	end

	local sandbox = action == "edit" and "workspace-write" or "read-only"
	local prompt = build_ephemeral_prompt(action, instruction, target)
	local stdout_lines = {}
	local stderr_lines = {}
	local stop_spinner = start_ephemeral_spinner(target.spinner_buf, target.spinner_line)
	local stop_diagnostic = start_ephemeral_diagnostic(action, target)
	local function stop_activity()
		stop_spinner()
		stop_diagnostic()
	end
	local command = {
		"codex",
		"exec",
		"--ephemeral",
		"--sandbox",
		sandbox,
		"--cd",
		vim.fn.getcwd(),
		"-",
	}

	notify("Started ephemeral Codex " .. action .. " over " .. target.kind)

	local job_id = vim.fn.jobstart(command, {
		stdin = "pipe",
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if data then
				vim.list_extend(stdout_lines, data)
			end
		end,
		on_stderr = function(_, data)
			if data then
				vim.list_extend(stderr_lines, data)
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				stop_activity()
				local result_path =
					open_result_file(make_result_lines(action, instruction, target, code, stdout_lines, stderr_lines))

				local level = code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
				local suffix = result_path and ": " .. vim.fn.fnamemodify(result_path, ":~") or ""
				notify("Ephemeral Codex " .. action .. " finished with code " .. code .. suffix, level)
			end)
		end,
	})

	if job_id <= 0 then
		stop_activity()
		notify("Failed to start ephemeral Codex " .. action .. " job", vim.log.levels.ERROR)
		return
	end

	vim.fn.chansend(job_id, prompt)
	vim.fn.chanclose(job_id, "stdin")
end

local function prompt_and_run_ephemeral(action, target)
	if not target then
		return
	end

	local prompt = action == "edit" and "Codex edit: " or "Codex command: "
	vim.ui.input({ prompt = prompt }, function(instruction)
		run_ephemeral(action, target, instruction)
	end)
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

function M.command_file()
	prompt_and_run_ephemeral("command", build_file_target())
end

function M.command_selection(opts)
	prompt_and_run_ephemeral("command", build_selection_target(opts))
end

function M.edit_file()
	prompt_and_run_ephemeral("edit", build_file_target())
end

function M.edit_selection(opts)
	prompt_and_run_ephemeral("edit", build_selection_target(opts))
end

function M.setup()
	if setup_done or vim.g.vscode then
		return
	end
	setup_done = true
	define_ephemeral_signs()

	vim.api.nvim_create_user_command("CodexChat", M.toggle, {})
	vim.api.nvim_create_user_command("CodexCommandFile", M.command_file, {})
	vim.api.nvim_create_user_command("CodexCommandSelection", M.command_selection, { range = true })
	vim.api.nvim_create_user_command("CodexEditFile", M.edit_file, {})
	vim.api.nvim_create_user_command("CodexEditSelection", M.edit_selection, { range = true })
	vim.api.nvim_create_user_command("CodexSendFile", M.send_file, {})
	vim.api.nvim_create_user_command("CodexSendLine", M.send_line, {})
	vim.api.nvim_create_user_command("CodexSendParagraph", M.send_paragraph, {})
	vim.api.nvim_create_user_command("CodexSendSelection", M.send_selection, { range = true })

	vim.keymap.set("n", "<leader>aa", M.toggle, { desc = "Codex: toggle chat" })
	vim.keymap.set("n", "<leader>ac", M.command_file, { desc = "Codex: command over file" })
	vim.keymap.set("x", "<leader>ac", M.command_selection, { desc = "Codex: command over selection" })
	vim.keymap.set("n", "<leader>ae", M.edit_file, { desc = "Codex: edit file" })
	vim.keymap.set("x", "<leader>ae", M.edit_selection, { desc = "Codex: edit selection" })
	vim.keymap.set("n", "<leader>af", M.send_file, { desc = "Codex: send file context" })
	vim.keymap.set("n", "<leader>al", M.send_line, { desc = "Codex: send line" })
	vim.keymap.set("n", "<leader>ap", M.send_paragraph, { desc = "Codex: send paragraph" })
	vim.keymap.set("x", "<leader>as", M.send_selection, { desc = "Codex: send selection" })
end

return M
