local M = {}

local CODEX_BUF_NAME = "codex://chat"
local CODEX_JOBS_BUF_NAME = "codex://jobs"
local CODEX_JOBS_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("codex-jobs")
local EPHEMERAL_RESULT_SUBDIR = "codex/ephemeral"
local EPHEMERAL_DIAGNOSTIC_NAMESPACE = vim.api.nvim_create_namespace("codex-ephemeral")
local EPHEMERAL_SPINNER_NAMESPACE = vim.api.nvim_create_namespace("codex-ephemeral-spinner")
local EPHEMERAL_RECENT_JOB_LIMIT = 20
local EPHEMERAL_SIGN_GROUP = "codex-ephemeral"
local EPHEMERAL_SPINNER_STYLES = {
	edit = {
		highlight = "DiagnosticWarn",
		verb = "editing",
		frames = {
			{ name = "CodexEphemeralEditSpinner1", text = "󰚩" },
			{ name = "CodexEphemeralEditSpinner2", text = "󰏫" },
			{ name = "CodexEphemeralEditSpinner3", text = "󰚩" },
			{ name = "CodexEphemeralEditSpinner4", text = "󰏬" },
		},
	},
	command = {
		highlight = "DiagnosticInfo",
		verb = "command over",
		frames = {
			{ name = "CodexEphemeralCommandSpinner1", text = "󰚩" },
			{ name = "CodexEphemeralCommandSpinner2", text = "" },
			{ name = "CodexEphemeralCommandSpinner3", text = "󰚩" },
			{ name = "CodexEphemeralCommandSpinner4", text = "" },
		},
	},
}
local EPHEMERAL_MODEL_CHOICES = {
	{ label = "CLI default", model = nil },
	{ label = "gpt-5.4-mini", model = "gpt-5.4-mini" },
	{ label = "gpt-5.4-nano", model = "gpt-5.4-nano" },
	{ label = "gpt-5.3-codex", model = "gpt-5.3-codex" },
	{ label = "gpt-5.3-codex-spark", model = "gpt-5.3-codex-spark" },
	{ label = "gpt-5.5", model = "gpt-5.5" },
	{ label = "Custom...", custom = true },
}
local EPHEMERAL_MODEL_TARGETS = {
	{ label = "Ephemeral edits", action = "edit" },
	{ label = "Ephemeral commands", action = "command" },
}
local codex_buf = nil
local codex_job_id = nil
local codex_jobs_buf = nil
local codex_jobs_line_highlights = {}
local codex_jobs_line_to_id = {}
local codex_jobs_preview_win = nil
local codex_jobs_win = nil
local previous_buf = nil
local active_ephemeral_diagnostics = {}
local ephemeral_jobs = {}
local ephemeral_job_order = {}
local next_ephemeral_job_id = 1
local next_ephemeral_diagnostic_id = 1
local next_ephemeral_result_id = 1
local next_ephemeral_sign_id = 1
local ephemeral_models = {
	command = nil,
	edit = nil,
}
local setup_done = false
local VISUAL_BLOCK_MODE = "\022"

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

local function is_valid_window(winid)
	return winid ~= nil and vim.api.nvim_win_is_valid(winid)
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

local function join_path(parent, child)
	if vim.fs and vim.fs.joinpath then
		return vim.fs.joinpath(parent, child)
	end

	local last_char = parent:sub(-1)
	if last_char == "/" or last_char == "\\" then
		return parent .. child
	end

	return parent .. package.config:sub(1, 1) .. child
end

local function buffer_file_context()
	local path = repo_relative_path(vim.api.nvim_buf_get_name(0))
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local filetype = vim.bo.filetype ~= "" and vim.bo.filetype or "unknown"
	local modified = vim.bo.modified and "yes" or "no"

	return path, line, filetype, modified
end

local function trim_whitespace(value)
	if value == nil then
		return ""
	end

	return tostring(value):match("^%s*(.-)%s*$")
end

local function trim_display(value, width)
	value = tostring(value or "")
	if #value <= width then
		return value
	end

	return value:sub(1, math.max(width - 3, 1)) .. "..."
end

local function job_instruction_display(job)
	local instruction = job and job.instruction or ""
	instruction = instruction:gsub("%s+", " ")
	return trim_whitespace(instruction)
end

local function ephemeral_model_display(model)
	return model and model ~= "" and model or "CLI default"
end

local function ephemeral_action_label(action)
	if action == "edit" then
		return "ephemeral edits"
	end
	if action == "command" then
		return "ephemeral commands"
	end

	return "ephemeral jobs"
end

local function set_ephemeral_model(action, model)
	if action ~= "edit" and action ~= "command" then
		notify("Unknown Codex ephemeral model target: " .. tostring(action), vim.log.levels.WARN)
		return
	end

	model = trim_whitespace(model)
	ephemeral_models[action] = model ~= "" and model or nil
	notify(
		"Codex " .. ephemeral_action_label(action) .. " model: " .. ephemeral_model_display(ephemeral_models[action])
	)
end

local function prompt_custom_ephemeral_model(action)
	vim.ui.input({
		prompt = "Codex " .. ephemeral_action_label(action) .. " model: ",
		default = ephemeral_models[action] or "",
	}, function(model)
		if model == nil then
			return
		end

		model = trim_whitespace(model)
		if model == "" then
			notify("Codex " .. ephemeral_action_label(action) .. " model unchanged")
			return
		end

		set_ephemeral_model(action, model)
	end)
end

local function ephemeral_model_choices(action)
	local choices = {}
	local current_model = ephemeral_models[action]
	local current_is_preset = false

	for _, choice in ipairs(EPHEMERAL_MODEL_CHOICES) do
		if not choice.custom and choice.model == current_model then
			current_is_preset = true
			break
		end
	end

	if current_model and not current_is_preset then
		table.insert(choices, { label = current_model, model = current_model, current = true })
	end

	vim.list_extend(choices, EPHEMERAL_MODEL_CHOICES)
	return choices
end

local function select_ephemeral_model(action)
	if action ~= "edit" and action ~= "command" then
		notify("Usage: CodexEphemeralModel [edit|command]", vim.log.levels.WARN)
		return
	end

	vim.ui.select(ephemeral_model_choices(action), {
		prompt = "Codex " .. ephemeral_action_label(action) .. " model (current: " .. ephemeral_model_display(
			ephemeral_models[action]
		) .. ")",
		format_item = function(choice)
			if choice.current then
				return choice.label .. " (current)"
			end

			if choice.custom then
				return choice.label
			end

			local suffix = ephemeral_models[action] == choice.model and " (current)" or ""
			return choice.label .. suffix
		end,
	}, function(choice)
		if not choice then
			return
		end

		if choice.custom then
			prompt_custom_ephemeral_model(action)
			return
		end

		set_ephemeral_model(action, choice.model)
	end)
end

local function select_ephemeral_model_target()
	vim.ui.select(EPHEMERAL_MODEL_TARGETS, {
		prompt = "Codex ephemeral model target",
		format_item = function(target)
			return target.label .. " (" .. ephemeral_model_display(ephemeral_models[target.action]) .. ")"
		end,
	}, function(target)
		if target then
			select_ephemeral_model(target.action)
		end
	end)
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

	if mode == VISUAL_BLOCK_MODE then
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
	if mode ~= "v" and mode ~= "V" and mode ~= VISUAL_BLOCK_MODE then
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

	return string.format("%s/codex-ephemeral-%s-%03d.md", get_ephemeral_result_dir(), os.date("%Y%m%d-%H%M%S"), id)
end

local function write_result_file(lines)
	local path = next_ephemeral_result_path()
	local ok = vim.fn.writefile(lines, path)

	if ok ~= 0 then
		notify("Failed to write ephemeral Codex result: " .. path, vim.log.levels.ERROR)
		return nil
	end

	return path
end

local function ephemeral_spinner_style(action)
	return EPHEMERAL_SPINNER_STYLES[action] or EPHEMERAL_SPINNER_STYLES.command
end

local function ephemeral_running_label(action, target, job)
	local style = ephemeral_spinner_style(action)
	local job_id = job and " #" .. job.id or ""

	return "Codex" .. job_id .. " " .. style.verb .. " " .. target.kind
end

local function ephemeral_spinner_label(action, target, job)
	local instruction = job_instruction_display(job)
	if instruction == "" then
		return ephemeral_running_label(action, target, job)
	end

	local job_id = job and " #" .. job.id or ""
	return "Codex" .. job_id .. " " .. action .. ": " .. trim_display(instruction, 48)
end

local function define_ephemeral_signs()
	for _, style in pairs(EPHEMERAL_SPINNER_STYLES) do
		for _, sign in ipairs(style.frames) do
			vim.fn.sign_define(sign.name, { text = sign.text, texthl = style.highlight })
		end
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

local function start_ephemeral_diagnostic(action, target, job)
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
			message = ephemeral_running_label(action, target, job),
		},
	}
	refresh_ephemeral_diagnostics(bufnr)

	return function()
		active_ephemeral_diagnostics[id] = nil
		refresh_ephemeral_diagnostics(bufnr)
	end
end

local function start_ephemeral_spinner(action, target, job)
	local bufnr = target.spinner_buf
	if not is_valid_buffer(bufnr) then
		return function() end
	end

	local style = ephemeral_spinner_style(action)
	local sign_id = next_ephemeral_sign_id
	next_ephemeral_sign_id = next_ephemeral_sign_id + 1

	local timer = vim.uv.new_timer()
	local extmark_id = nil
	local frame = 1
	local running = true

	local function target_line()
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		return math.min(math.max(target.spinner_line, 1), math.max(line_count, 1))
	end

	local function place_sign()
		if not running or not is_valid_buffer(bufnr) then
			return
		end

		local line = target_line()
		local sign = style.frames[frame]
		vim.fn.sign_place(sign_id, EPHEMERAL_SIGN_GROUP, sign.name, bufnr, {
			lnum = line,
			priority = 30,
		})

		local ok, next_extmark_id =
			pcall(vim.api.nvim_buf_set_extmark, bufnr, EPHEMERAL_SPINNER_NAMESPACE, line - 1, 0, {
				id = extmark_id,
				virt_text = {
					{ " " .. sign.text .. " " .. ephemeral_spinner_label(action, target, job), style.highlight },
				},
				virt_text_pos = "eol",
				hl_mode = "combine",
			})
		if ok then
			extmark_id = next_extmark_id
		end

		frame = frame % #style.frames + 1
	end

	place_sign()
	timer:start(200, 300, function()
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
			if extmark_id then
				pcall(vim.api.nvim_buf_del_extmark, bufnr, EPHEMERAL_SPINNER_NAMESPACE, extmark_id)
			end
		end
	end
end

local render_codex_jobs_panel

local function is_ephemeral_job_active(job)
	return job.status == "starting" or job.status == "running" or job.status == "cancelling"
end

local function prune_ephemeral_jobs()
	local completed = {}
	for _, id in ipairs(ephemeral_job_order) do
		local job = ephemeral_jobs[id]
		if job and not is_ephemeral_job_active(job) then
			table.insert(completed, id)
		end
	end

	while #completed > EPHEMERAL_RECENT_JOB_LIMIT do
		local id = table.remove(completed, 1)
		ephemeral_jobs[id] = nil
	end

	local next_order = {}
	for _, id in ipairs(ephemeral_job_order) do
		if ephemeral_jobs[id] then
			table.insert(next_order, id)
		end
	end
	ephemeral_job_order = next_order
end

local function refresh_open_codex_jobs_panel()
	if is_valid_buffer(codex_jobs_buf) and render_codex_jobs_panel then
		render_codex_jobs_panel()
	end
end

local function create_ephemeral_job_record(action, target, model, instruction)
	local id = next_ephemeral_job_id
	next_ephemeral_job_id = next_ephemeral_job_id + 1

	local job = {
		id = id,
		action = action,
		cancel_requested = false,
		exit_code = nil,
		finished_at = nil,
		instruction = instruction,
		job_id = nil,
		kind = target.kind,
		model = model,
		path = target.path,
		result_path = nil,
		start_line = target.start_line,
		started_at = os.time(),
		status = "starting",
		end_line = target.end_line,
	}
	ephemeral_jobs[id] = job
	table.insert(ephemeral_job_order, id)
	refresh_open_codex_jobs_panel()

	return job
end

local function update_ephemeral_job(job, attrs)
	if not job then
		return
	end

	for key, value in pairs(attrs) do
		job[key] = value
	end

	if job.finished_at then
		prune_ephemeral_jobs()
	end
	refresh_open_codex_jobs_panel()
end

local function delete_ephemeral_job(job)
	if not job then
		notify("Codex job not found", vim.log.levels.WARN)
		return false
	end

	if is_ephemeral_job_active(job) then
		notify("Codex job #" .. job.id .. " is still running; cancel it with x first", vim.log.levels.WARN)
		return false
	end

	ephemeral_jobs[job.id] = nil
	local next_order = {}
	for _, id in ipairs(ephemeral_job_order) do
		if id ~= job.id then
			table.insert(next_order, id)
		end
	end
	ephemeral_job_order = next_order
	refresh_open_codex_jobs_panel()
	notify("Deleted Codex job #" .. job.id .. " from the session list")
	return true
end

local function delete_ephemeral_job_by_id(id)
	return delete_ephemeral_job(ephemeral_jobs[tonumber(id)])
end

local function close_codex_jobs_panel()
	if is_valid_window(codex_jobs_win) then
		vim.api.nvim_win_close(codex_jobs_win, true)
	end
	codex_jobs_win = nil
end

local function close_codex_jobs_preview()
	if is_valid_window(codex_jobs_preview_win) then
		vim.api.nvim_win_close(codex_jobs_preview_win, true)
	end
	codex_jobs_preview_win = nil
end

local function selected_ephemeral_job()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local id = codex_jobs_line_to_id[line]
	if not id then
		return nil
	end

	return ephemeral_jobs[id]
end

local function jump_to_ephemeral_job_source(job)
	if not job or job.path == "" or job.path == "[No Name]" then
		notify("No source file for Codex job", vim.log.levels.WARN)
		return
	end

	close_codex_jobs_panel()
	vim.cmd("edit " .. vim.fn.fnameescape(job.path))
	pcall(vim.api.nvim_win_set_cursor, 0, { math.max(job.start_line or 1, 1), 0 })
end

local function open_ephemeral_job_result(job)
	if not job or not job.result_path or vim.fn.filereadable(job.result_path) ~= 1 then
		notify("No result file for Codex job", vim.log.levels.WARN)
		return false
	end

	close_codex_jobs_panel()
	vim.cmd("edit " .. vim.fn.fnameescape(job.result_path))
	vim.bo.filetype = "markdown"
	return true
end

local function open_selected_ephemeral_job()
	local job = selected_ephemeral_job()
	if not job then
		return
	end

	if open_ephemeral_job_result(job) then
		return
	end
	jump_to_ephemeral_job_source(job)
end

local function jump_to_selected_ephemeral_job_source()
	jump_to_ephemeral_job_source(selected_ephemeral_job())
end

local function open_selected_ephemeral_job_result()
	open_ephemeral_job_result(selected_ephemeral_job())
end

local function preview_ephemeral_job_instruction(job)
	if not job then
		notify("No Codex job under cursor", vim.log.levels.WARN)
		return
	end

	close_codex_jobs_preview()

	local line_range = "?"
	if job.start_line and job.end_line then
		line_range = job.start_line == job.end_line and tostring(job.start_line)
			or job.start_line .. "-" .. job.end_line
	end

	local lines = {
		"Codex Job #" .. job.id,
		"",
		"Action: " .. job.action,
		"Target: " .. job.kind,
		"Model: " .. ephemeral_model_display(job.model),
		"Status: " .. job.status,
		"Location: " .. job.path .. ":" .. line_range,
		"",
		"Instruction:",
		"",
	}
	vim.list_extend(lines, vim.split(job.instruction or "", "\n", { plain = true }))

	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].filetype = "markdown"
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].swapfile = false

	local columns = vim.o.columns
	local editor_lines = vim.o.lines
	local width = math.min(math.max(math.floor(columns * 0.72), 60), math.max(columns - 6, 20))
	local height = math.min(math.max(#lines, 12), math.max(editor_lines - 8, 8))
	codex_jobs_preview_win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		row = math.max(math.floor((editor_lines - height) / 2), 0),
		col = math.max(math.floor((columns - width) / 2), 0),
		width = width,
		height = height,
		border = "rounded",
		style = "minimal",
		title = " Codex Job Command ",
		title_pos = "center",
	})
	vim.wo[codex_jobs_preview_win].number = false
	vim.wo[codex_jobs_preview_win].relativenumber = false
	vim.wo[codex_jobs_preview_win].signcolumn = "no"
	vim.wo[codex_jobs_preview_win].wrap = true

	local opts = { buffer = bufnr, nowait = true, silent = true }
	vim.keymap.set("n", "q", close_codex_jobs_preview, opts)
	vim.keymap.set("n", "<Esc>", close_codex_jobs_preview, opts)
end

local function preview_selected_ephemeral_job_instruction()
	preview_ephemeral_job_instruction(selected_ephemeral_job())
end

local function cancel_selected_ephemeral_job()
	local job = selected_ephemeral_job()
	if not job or not is_ephemeral_job_active(job) or not job.job_id then
		notify("No running Codex job under cursor", vim.log.levels.WARN)
		return
	end

	job.cancel_requested = true
	job.status = "cancelling"
	vim.fn.jobstop(job.job_id)
	refresh_open_codex_jobs_panel()
	notify("Cancelling Codex job #" .. job.id)
end

local function delete_selected_ephemeral_job()
	delete_ephemeral_job(selected_ephemeral_job())
end

local function ensure_codex_jobs_buffer()
	if is_valid_buffer(codex_jobs_buf) then
		return codex_jobs_buf
	end

	local existing = vim.fn.bufnr(CODEX_JOBS_BUF_NAME)
	if existing > 0 and is_valid_buffer(existing) then
		codex_jobs_buf = existing
	else
		codex_jobs_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(codex_jobs_buf, CODEX_JOBS_BUF_NAME)
	end

	vim.bo[codex_jobs_buf].bufhidden = "hide"
	vim.bo[codex_jobs_buf].buftype = "nofile"
	vim.bo[codex_jobs_buf].filetype = "codexjobs"
	vim.bo[codex_jobs_buf].modifiable = false
	vim.bo[codex_jobs_buf].swapfile = false

	local opts = { buffer = codex_jobs_buf, nowait = true, silent = true }
	vim.keymap.set("n", "q", close_codex_jobs_panel, opts)
	vim.keymap.set("n", "<Esc>", close_codex_jobs_panel, opts)
	vim.keymap.set("n", "r", refresh_open_codex_jobs_panel, opts)
	vim.keymap.set("n", "<CR>", open_selected_ephemeral_job, opts)
	vim.keymap.set("n", "d", delete_selected_ephemeral_job, opts)
	vim.keymap.set("n", "g", jump_to_selected_ephemeral_job_source, opts)
	vim.keymap.set("n", "o", open_selected_ephemeral_job_result, opts)
	vim.keymap.set("n", "p", preview_selected_ephemeral_job_instruction, opts)
	vim.keymap.set("n", "x", cancel_selected_ephemeral_job, opts)

	return codex_jobs_buf
end

local function split_ephemeral_jobs()
	local running = {}
	local completed = {}

	for index = #ephemeral_job_order, 1, -1 do
		local job = ephemeral_jobs[ephemeral_job_order[index]]
		if job and is_ephemeral_job_active(job) then
			table.insert(running, job)
		end
	end

	for index = #ephemeral_job_order, 1, -1 do
		local job = ephemeral_jobs[ephemeral_job_order[index]]
		if job and not is_ephemeral_job_active(job) then
			table.insert(completed, job)
		end
	end

	return running, completed
end

local function job_line_range(job)
	if not job.start_line or not job.end_line then
		return "?"
	end

	if job.start_line == job.end_line then
		return tostring(job.start_line)
	end

	return job.start_line .. "-" .. job.end_line
end

local function job_age(job)
	local finished_at = job.finished_at or os.time()
	return math.max(finished_at - job.started_at, 0) .. "s"
end

local function job_status_label(job)
	if job.status == "starting" or job.status == "running" then
		return "RUN"
	end
	if job.status == "cancelling" then
		return "CXL..."
	end
	if job.status == "failed_to_start" then
		return "START-ERR"
	end
	if job.status == "success" then
		return "OK"
	end
	if job.status == "failed" then
		return "ERR"
	end
	if job.status == "cancelled" then
		return "CXL"
	end

	return job.status
end

local function job_status_highlight(job)
	if job.status == "success" then
		return "DiagnosticOk"
	end
	if job.status == "failed" or job.status == "failed_to_start" then
		return "DiagnosticError"
	end
	if job.status == "cancelled" or job.status == "cancelling" then
		return "DiagnosticWarn"
	end

	return "DiagnosticInfo"
end

local function job_location(job)
	return job.path .. ":" .. job_line_range(job)
end

local function job_result_display(job)
	if not job.result_path then
		return "-"
	end

	return vim.fn.fnamemodify(job.result_path, ":~:.")
end

local function job_model_display(job)
	return ephemeral_model_display(job.model)
end

local function build_codex_jobs_lines()
	local lines = {
		"Codex Jobs",
		"",
		"Keys: <CR> open/jump  o result  g source  p preview  x cancel  d delete  r refresh  q close",
		"",
	}
	codex_jobs_line_to_id = {}
	codex_jobs_line_highlights = {
		[1] = "Title",
		[3] = "Comment",
	}

	local active_jobs, recent_jobs = split_ephemeral_jobs()
	if #active_jobs == 0 and #recent_jobs == 0 then
		table.insert(lines, "No ephemeral Codex jobs in this session.")
		codex_jobs_line_highlights[#lines] = "Comment"
		return lines
	end

	local function append_section(title, jobs)
		if #jobs == 0 then
			return
		end

		table.insert(lines, title)
		codex_jobs_line_highlights[#lines] = "Statement"
		table.insert(
			lines,
			string.format(
				"%-4s %-9s %-7s %-9s %-32s %-14s %-38s %-6s %s",
				"ID",
				"Status",
				"Action",
				"Target",
				"Command",
				"Model",
				"Location",
				"Age",
				"Result"
			)
		)
		codex_jobs_line_highlights[#lines] = "Type"

		for _, job in ipairs(jobs) do
			local exit = job.exit_code and " exit=" .. job.exit_code or ""
			local line = string.format(
				"%-4d %-9s %-7s %-9s %-32s %-14s %-38s %-6s %s",
				job.id,
				job_status_label(job),
				job.action,
				job.kind,
				trim_display(job_instruction_display(job), 32),
				trim_display(job_model_display(job), 14),
				trim_display(job_location(job), 38),
				job_age(job),
				trim_display(job_result_display(job) .. exit, 42)
			)
			table.insert(lines, line)
			codex_jobs_line_to_id[#lines] = job.id
			codex_jobs_line_highlights[#lines] = job_status_highlight(job)
		end

		table.insert(lines, "")
	end

	append_section("Active", active_jobs)
	append_section("Recent", recent_jobs)

	return lines
end

local function codex_jobs_float_config()
	local columns = vim.o.columns
	local editor_lines = vim.o.lines
	local width = math.min(math.max(math.floor(columns * 0.92), 88), math.max(columns - 2, 20))
	local available_height = math.max(editor_lines - 4, 8)
	local max_height = math.min(available_height, math.max(math.floor(editor_lines * 0.8), 8))
	local height = max_height

	return {
		relative = "editor",
		row = math.max(math.floor((editor_lines - height) / 2), 0),
		col = math.max(math.floor((columns - width) / 2), 0),
		width = width,
		height = height,
		border = "rounded",
		style = "minimal",
		title = " Codex Jobs ",
		title_pos = "center",
	}
end

render_codex_jobs_panel = function()
	if not is_valid_buffer(codex_jobs_buf) then
		return
	end

	local lines = build_codex_jobs_lines()
	vim.bo[codex_jobs_buf].modifiable = true
	vim.api.nvim_buf_set_lines(codex_jobs_buf, 0, -1, false, lines)
	vim.bo[codex_jobs_buf].modified = false
	vim.bo[codex_jobs_buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(codex_jobs_buf, CODEX_JOBS_HIGHLIGHT_NAMESPACE, 0, -1)

	for line, highlight in pairs(codex_jobs_line_highlights) do
		vim.api.nvim_buf_add_highlight(codex_jobs_buf, CODEX_JOBS_HIGHLIGHT_NAMESPACE, highlight, line - 1, 0, -1)
	end

	if is_valid_window(codex_jobs_win) then
		vim.api.nvim_win_set_config(codex_jobs_win, codex_jobs_float_config())
	end
end

local function open_codex_jobs_panel()
	local bufnr = ensure_codex_jobs_buffer()
	if is_valid_window(codex_jobs_win) then
		vim.api.nvim_set_current_win(codex_jobs_win)
		render_codex_jobs_panel()
		return
	end

	codex_jobs_win = vim.api.nvim_open_win(bufnr, true, codex_jobs_float_config())
	vim.wo[codex_jobs_win].cursorline = true
	vim.wo[codex_jobs_win].number = false
	vim.wo[codex_jobs_win].relativenumber = false
	vim.wo[codex_jobs_win].signcolumn = "no"
	vim.wo[codex_jobs_win].wrap = false
	render_codex_jobs_panel()
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
		mode_description =
			"Apply the user's requested edits if appropriate. Keep changes scoped to the supplied context."
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

local function make_result_lines(action, instruction, target, model, exit_code, stdout_lines, stderr_lines)
	local lines = {
		"# Codex Ephemeral Result",
		"",
		"- Action: " .. action,
		"- Target: " .. target.kind,
		"- Model: " .. ephemeral_model_display(model),
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
	}
	vim.list_extend(lines, stdout_lines)
	vim.list_extend(lines, {
		"",
		"## Stderr",
		"",
	})
	vim.list_extend(lines, stderr_lines)

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
	local model = ephemeral_models[action]
	local prompt = build_ephemeral_prompt(action, instruction, target)
	local stdout_lines = {}
	local stderr_lines = {}
	local job_record = create_ephemeral_job_record(action, target, model, instruction)
	local stop_spinner = start_ephemeral_spinner(action, target, job_record)
	local stop_diagnostic = start_ephemeral_diagnostic(action, target, job_record)
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

	if model then
		table.insert(command, 3, "--model")
		table.insert(command, 4, model)
	end

	notify(
		"Started ephemeral Codex "
			.. action
			.. " over "
			.. target.kind
			.. " with model "
			.. ephemeral_model_display(model)
	)

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
				local result_path = write_result_file(
					make_result_lines(action, instruction, target, model, code, stdout_lines, stderr_lines)
				)
				local status = job_record.cancel_requested and "cancelled" or (code == 0 and "success" or "failed")
				update_ephemeral_job(job_record, {
					exit_code = code,
					finished_at = os.time(),
					result_path = result_path,
					status = status,
				})

				local level = (status == "success" or status == "cancelled") and vim.log.levels.INFO
					or vim.log.levels.WARN
				local suffix = result_path and ": " .. vim.fn.fnamemodify(result_path, ":~") or ""
				notify(
					"Ephemeral Codex "
						.. action
						.. " "
						.. status
						.. " with model "
						.. ephemeral_model_display(model)
						.. " and code "
						.. code
						.. suffix,
					level
				)
			end)
		end,
	})

	if job_id <= 0 then
		stop_activity()
		update_ephemeral_job(job_record, {
			finished_at = os.time(),
			status = "failed_to_start",
		})
		notify("Failed to start ephemeral Codex " .. action .. " job", vim.log.levels.ERROR)
		return
	end

	update_ephemeral_job(job_record, {
		job_id = job_id,
		status = "running",
	})
	vim.fn.chansend(job_id, prompt)
	vim.fn.chanclose(job_id, "stdin")
end

---Prompt for an instruction and run an ephemeral Codex job for the given target.
---
---The action controls both the input prompt label and how the job is executed:
---"edit" requests an edit, while any other action is treated as a command.
---If no target can be built, this returns without prompting.
---@param action string
---@param target table|nil
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

local function build_oil_selection_entries(oil, bufnr, directory, start_line, end_line)
	local entries = {}
	local seen_paths = {}

	for line = start_line, end_line do
		local entry = oil.get_entry_on_line(bufnr, line)
		local name = entry and trim_whitespace(entry.parsed_name or entry.name)

		if name and name ~= "" then
			local path = join_path(directory, name)
			if not seen_paths[path] then
				seen_paths[path] = true
				table.insert(entries, {
					path = repo_relative_path(path),
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
		"Directory: " .. repo_relative_path(directory),
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

	if paste_to_codex(table.concat(prompt_lines, "\n")) then
		notify("Sent Oil selection to Codex: " .. repo_relative_path(directory) .. ":" .. start_line .. "-" .. end_line)
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

function M.toggle_jobs()
	if is_valid_window(codex_jobs_win) then
		close_codex_jobs_panel()
		return
	end

	open_codex_jobs_panel()
end

function M.delete_job(opts)
	local id = opts and opts.args and opts.args ~= "" and opts.args or nil
	if id then
		delete_ephemeral_job_by_id(id)
		return
	end

	if is_valid_window(codex_jobs_win) and vim.api.nvim_get_current_win() == codex_jobs_win then
		delete_selected_ephemeral_job()
		return
	end

	notify("Usage: CodexJobsDelete <id>", vim.log.levels.WARN)
end

function M.select_ephemeral_model(opts)
	local action = opts and trim_whitespace(opts.args) or ""
	if action == "" then
		select_ephemeral_model_target()
		return
	end

	select_ephemeral_model(action)
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
	vim.api.nvim_create_user_command("CodexEphemeralModel", M.select_ephemeral_model, {
		complete = function()
			return { "edit", "command" }
		end,
		nargs = "?",
	})
	vim.api.nvim_create_user_command("CodexJobs", M.toggle_jobs, {})
	vim.api.nvim_create_user_command("CodexJobsDelete", M.delete_job, { nargs = "?" })
	vim.api.nvim_create_user_command("CodexSendFile", M.send_file, {})
	vim.api.nvim_create_user_command("CodexSendLine", M.send_line, {})
	vim.api.nvim_create_user_command("CodexSendParagraph", M.send_paragraph, {})
	vim.api.nvim_create_user_command("CodexSendSelection", M.send_selection, { range = true })

	vim.keymap.set("n", "<leader>aj", M.toggle_jobs, { desc = "Codex: jobs" })
	vim.keymap.set("n", "<leader>aa", M.toggle, { desc = "Codex: toggle chat" })
	vim.keymap.set("n", "<leader>ac", M.command_file, { desc = "Codex: command over file" })
	vim.keymap.set("x", "<leader>ac", M.command_selection, { desc = "Codex: command over selection" })
	vim.keymap.set("n", "<leader>ae", M.edit_file, { desc = "Codex: edit file" })
	vim.keymap.set("x", "<leader>ae", M.edit_selection, { desc = "Codex: edit selection" })
	vim.keymap.set("n", "<leader>af", M.send_file, { desc = "Codex: send file context" })
	vim.keymap.set("n", "<leader>al", M.send_line, { desc = "Codex: send line" })
	vim.keymap.set("n", "<leader>am", M.select_ephemeral_model, { desc = "Codex: ephemeral model" })
	vim.keymap.set("n", "<leader>ap", M.send_paragraph, { desc = "Codex: send paragraph" })
	vim.keymap.set("x", "<leader>as", M.send_selection, { desc = "Codex: send selection" })
end

return M
