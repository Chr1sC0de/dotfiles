local constants = require("codex.constants")
local jobs = require("codex.ephemeral.jobs")
local model = require("codex.ephemeral.model")
local state = require("codex.state")
local util = require("codex.util")

local M = {}

function M.close()
	if util.is_valid_window(state.codex_jobs_win) then
		vim.api.nvim_win_close(state.codex_jobs_win, true)
	end
	state.codex_jobs_win = nil
end

function M.close_preview()
	if util.is_valid_window(state.codex_jobs_preview_win) then
		vim.api.nvim_win_close(state.codex_jobs_preview_win, true)
	end
	state.codex_jobs_preview_win = nil
end

function M.selected()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local id = state.codex_jobs_line_to_id[line]
	if not id then
		return nil
	end

	return state.ephemeral_jobs[id]
end

function M.jump_to_source(job)
	if not job or job.path == "" or job.path == "[No Name]" then
		util.notify("No source file for Codex job", vim.log.levels.WARN)
		return
	end

	M.close()
	vim.cmd("edit " .. vim.fn.fnameescape(job.path))
	pcall(vim.api.nvim_win_set_cursor, 0, { math.max(job.start_line or 1, 1), 0 })
end

function M.open_result(job)
	if not job or not job.result_path or vim.fn.filereadable(job.result_path) ~= 1 then
		util.notify("No result file for Codex job", vim.log.levels.WARN)
		return false
	end

	M.close()
	vim.cmd("edit " .. vim.fn.fnameescape(job.result_path))
	vim.bo.filetype = "markdown"
	return true
end

local function open_selected_ephemeral_job()
	local job = M.selected()
	if not job then
		return
	end

	if M.open_result(job) then
		return
	end
	M.jump_to_source(job)
end

local function jump_to_selected_ephemeral_job_source()
	M.jump_to_source(M.selected())
end

local function open_selected_ephemeral_job_result()
	M.open_result(M.selected())
end

local function preview_ephemeral_job_instruction(job)
	if not job then
		util.notify("No Codex job under cursor", vim.log.levels.WARN)
		return
	end

	M.close_preview()

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
		"Model: " .. model.display(job.model),
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
	state.codex_jobs_preview_win = vim.api.nvim_open_win(bufnr, true, {
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
	vim.wo[state.codex_jobs_preview_win].number = false
	vim.wo[state.codex_jobs_preview_win].relativenumber = false
	vim.wo[state.codex_jobs_preview_win].signcolumn = "no"
	vim.wo[state.codex_jobs_preview_win].wrap = true

	local opts = { buffer = bufnr, nowait = true, silent = true }
	vim.keymap.set("n", "q", M.close_preview, opts)
	vim.keymap.set("n", "<Esc>", M.close_preview, opts)
end

local function preview_selected_ephemeral_job_instruction()
	preview_ephemeral_job_instruction(M.selected())
end

local function cancel_selected_ephemeral_job()
	local job = M.selected()
	if not job or not jobs.is_active(job) or not job.job_id then
		util.notify("No running Codex job under cursor", vim.log.levels.WARN)
		return
	end

	job.cancel_requested = true
	job.status = "cancelling"
	vim.fn.jobstop(job.job_id)
	M.refresh_open()
	util.notify("Cancelling Codex job #" .. job.id)
end

function M.delete_selected()
	jobs.delete(M.selected())
end

local function ensure_codex_jobs_buffer()
	if util.is_valid_buffer(state.codex_jobs_buf) then
		return state.codex_jobs_buf
	end

	local existing = vim.fn.bufnr(constants.CODEX_JOBS_BUF_NAME)
	if existing > 0 and util.is_valid_buffer(existing) then
		state.codex_jobs_buf = existing
	else
		state.codex_jobs_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(state.codex_jobs_buf, constants.CODEX_JOBS_BUF_NAME)
	end

	vim.bo[state.codex_jobs_buf].bufhidden = "hide"
	vim.bo[state.codex_jobs_buf].buftype = "nofile"
	vim.bo[state.codex_jobs_buf].filetype = "codexjobs"
	vim.bo[state.codex_jobs_buf].modifiable = false
	vim.bo[state.codex_jobs_buf].swapfile = false

	local opts = { buffer = state.codex_jobs_buf, nowait = true, silent = true }
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
	vim.keymap.set("n", "r", M.refresh_open, opts)
	vim.keymap.set("n", "<CR>", open_selected_ephemeral_job, opts)
	vim.keymap.set("n", "d", M.delete_selected, opts)
	vim.keymap.set("n", "g", jump_to_selected_ephemeral_job_source, opts)
	vim.keymap.set("n", "o", open_selected_ephemeral_job_result, opts)
	vim.keymap.set("n", "p", preview_selected_ephemeral_job_instruction, opts)
	vim.keymap.set("n", "x", cancel_selected_ephemeral_job, opts)

	return state.codex_jobs_buf
end

local function split_ephemeral_jobs()
	local running = {}
	local completed = {}

	for index = #state.ephemeral_job_order, 1, -1 do
		local job = state.ephemeral_jobs[state.ephemeral_job_order[index]]
		if job and jobs.is_active(job) then
			table.insert(running, job)
		end
	end

	for index = #state.ephemeral_job_order, 1, -1 do
		local job = state.ephemeral_jobs[state.ephemeral_job_order[index]]
		if job and not jobs.is_active(job) then
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
	return model.display(job.model)
end

local function build_codex_jobs_lines()
	local lines = {
		"Codex Jobs",
		"",
		"Keys: <CR> open/jump  o result  g source  p preview  x cancel  d delete  r refresh  q close",
		"",
	}
	state.codex_jobs_line_to_id = {}
	state.codex_jobs_line_highlights = {
		[1] = "Title",
		[3] = "Comment",
	}

	local active_jobs, recent_jobs = split_ephemeral_jobs()
	if #active_jobs == 0 and #recent_jobs == 0 then
		table.insert(lines, "No ephemeral Codex jobs in this session.")
		state.codex_jobs_line_highlights[#lines] = "Comment"
		return lines
	end

	local function append_section(title, section_jobs)
		if #section_jobs == 0 then
			return
		end

		table.insert(lines, title)
		state.codex_jobs_line_highlights[#lines] = "Statement"
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
		state.codex_jobs_line_highlights[#lines] = "Type"

		for _, job in ipairs(section_jobs) do
			local exit = job.exit_code and " exit=" .. job.exit_code or ""
			local line = string.format(
				"%-4d %-9s %-7s %-9s %-32s %-14s %-38s %-6s %s",
				job.id,
				job_status_label(job),
				job.action,
				job.kind,
				util.trim_display(util.job_instruction_display(job), 32),
				util.trim_display(job_model_display(job), 14),
				util.trim_display(job_location(job), 38),
				job_age(job),
				util.trim_display(job_result_display(job) .. exit, 42)
			)
			table.insert(lines, line)
			state.codex_jobs_line_to_id[#lines] = job.id
			state.codex_jobs_line_highlights[#lines] = job_status_highlight(job)
		end

		table.insert(lines, "")
	end

	append_section("Active", active_jobs)
	append_section("Recent", recent_jobs)

	return lines
end

local function first_selectable_job_line()
	local first_line = nil
	for line, id in pairs(state.codex_jobs_line_to_id) do
		if id and (not first_line or line < first_line) then
			first_line = line
		end
	end

	return first_line
end

local function focus_first_selectable_job_line()
	if not util.is_valid_window(state.codex_jobs_win) then
		return
	end

	local line = first_selectable_job_line()
	if not line then
		return
	end

	pcall(vim.api.nvim_win_set_cursor, state.codex_jobs_win, { line, 0 })
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

function M.render()
	if not util.is_valid_buffer(state.codex_jobs_buf) then
		return
	end

	local lines = build_codex_jobs_lines()
	vim.bo[state.codex_jobs_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.codex_jobs_buf, 0, -1, false, lines)
	vim.bo[state.codex_jobs_buf].modified = false
	vim.bo[state.codex_jobs_buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.codex_jobs_buf, constants.CODEX_JOBS_HIGHLIGHT_NAMESPACE, 0, -1)

	for line, highlight in pairs(state.codex_jobs_line_highlights) do
		vim.api.nvim_buf_add_highlight(
			state.codex_jobs_buf,
			constants.CODEX_JOBS_HIGHLIGHT_NAMESPACE,
			highlight,
			line - 1,
			0,
			-1
		)
	end

	if util.is_valid_window(state.codex_jobs_win) then
		vim.api.nvim_win_set_config(state.codex_jobs_win, codex_jobs_float_config())
	end
end

function M.refresh_open()
	if util.is_valid_buffer(state.codex_jobs_buf) then
		M.render()
	end
end

function M.open()
	local bufnr = ensure_codex_jobs_buffer()
	if util.is_valid_window(state.codex_jobs_win) then
		vim.api.nvim_set_current_win(state.codex_jobs_win)
		M.render()
		return
	end

	state.codex_jobs_win = vim.api.nvim_open_win(bufnr, true, codex_jobs_float_config())
	vim.wo[state.codex_jobs_win].cursorline = true
	vim.wo[state.codex_jobs_win].number = false
	vim.wo[state.codex_jobs_win].relativenumber = false
	vim.wo[state.codex_jobs_win].signcolumn = "no"
	vim.wo[state.codex_jobs_win].wrap = false
	M.render()
	focus_first_selectable_job_line()
end

function M.toggle()
	if util.is_valid_window(state.codex_jobs_win) then
		M.close()
		return
	end

	M.open()
end

function M.is_current_window()
	return util.is_valid_window(state.codex_jobs_win) and vim.api.nvim_get_current_win() == state.codex_jobs_win
end

return M
