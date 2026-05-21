local constants = require("codex.constants")
local state = require("codex.state")
local util = require("codex.util")

--- Utility functions for launching and interacting with Codex terminal chat buffers.
local M = {}

local function ensure_session_state()
	state.codex_deleted_jobs = state.codex_deleted_jobs or {}
	state.codex_sessions = state.codex_sessions or {}
	state.codex_session_order = state.codex_session_order or {}
	state.next_codex_session_id = state.next_codex_session_id or 1
end

local function remove_from_order(bufnr)
	for index = #state.codex_session_order, 1, -1 do
		if state.codex_session_order[index] == bufnr then
			table.remove(state.codex_session_order, index)
		end
	end
end

local function append_to_order(bufnr)
	remove_from_order(bufnr)
	table.insert(state.codex_session_order, bufnr)
end

local function sync_active_state(session)
	if session then
		state.codex_active_buf = session.bufnr
		state.codex_buf = session.bufnr
		state.codex_job_id = session.job_id
		return
	end

	state.codex_active_buf = nil
	state.codex_buf = nil
	state.codex_job_id = nil
end

local function register_existing_buffer(bufnr)
	if not util.is_valid_buffer(bufnr) or vim.b[bufnr].codex_chat ~= true then
		return nil
	end

	local id = vim.b[bufnr].codex_session_id or state.next_codex_session_id
	state.next_codex_session_id = math.max(state.next_codex_session_id, id + 1)

	local session = {
		id = id,
		bufnr = bufnr,
		cwd = vim.b[bufnr].codex_cwd or vim.fn.getcwd(),
		started_at = vim.b[bufnr].codex_started_at or os.time(),
		job_id = vim.b[bufnr].codex_job_id or vim.b[bufnr].terminal_job_id,
		exited = vim.b[bufnr].codex_exited == true,
		exit_code = vim.b[bufnr].codex_exit_code,
		title = vim.b[bufnr].codex_title,
	}

	state.codex_sessions[bufnr] = session
	append_to_order(bufnr)
	return session
end

local function session_for_buffer(bufnr)
	ensure_session_state()
	bufnr = tonumber(bufnr)
	if not bufnr then
		return nil
	end

	return state.codex_sessions[bufnr] or register_existing_buffer(bufnr)
end

local function session_is_running(session)
	if not session or session.exited or not util.is_valid_buffer(session.bufnr) or not session.job_id then
		return false
	end

	return vim.fn.jobwait({ session.job_id }, 0)[1] == -1
end

local function delete_session_buffer(bufnr)
	if util.is_valid_buffer(bufnr) then
		pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	end
end

local function remove_session(bufnr, opts)
	opts = opts or {}
	local session = state.codex_sessions[bufnr]

	if session and session.title_job_id then
		pcall(vim.fn.jobstop, session.title_job_id)
	end
	if session and session.title_output_path then
		pcall(vim.fn.delete, session.title_output_path)
	end

	state.codex_sessions[bufnr] = nil
	remove_from_order(bufnr)

	if state.codex_active_buf == bufnr or state.codex_buf == bufnr then
		sync_active_state(nil)
	end

	if opts.delete_buffer and session then
		delete_session_buffer(bufnr)
	end
end

local function refresh_chat_panel()
	local ok, panel = pcall(require, "codex.chat_panel")
	if ok then
		panel.refresh_open()
	end
end

local function newest_live_session()
	for index = #state.codex_session_order, 1, -1 do
		local session = session_for_buffer(state.codex_session_order[index])
		if session_is_running(session) then
			return session
		end
	end

	return nil
end

---Removes exited or deleted Codex chat sessions from the registry.
function M.cleanup()
	ensure_session_state()
	local order = vim.list_extend({}, state.codex_session_order)

	for _, bufnr in ipairs(order) do
		local session = state.codex_sessions[bufnr]
		if not session or not util.is_valid_buffer(bufnr) or session.exited or not session_is_running(session) then
			remove_session(bufnr, { delete_buffer = util.is_valid_buffer(bufnr) })
		end
	end

	if state.codex_active_buf and not session_is_running(session_for_buffer(state.codex_active_buf)) then
		sync_active_state(nil)
	end
end

---Returns true when the given Codex job is active.
---
---@param bufnr? integer target buffer; defaults to the active Codex target.
---@return boolean
function M.is_running(bufnr)
	local session = session_for_buffer(bufnr or state.codex_active_buf)
	return session_is_running(session)
end

---Returns the current active Codex chat session, if one is live.
---
---@return table|nil
function M.active_session()
	M.cleanup()

	local session = session_for_buffer(state.codex_active_buf)
	if session_is_running(session) then
		sync_active_state(session)
		return session
	end

	session = newest_live_session()
	if session then
		sync_active_state(session)
		return session
	end

	sync_active_state(nil)
	return nil
end

---@return integer|nil
function M.active_bufnr()
	local session = M.active_session()
	return session and session.bufnr or nil
end

---Returns live Codex chat sessions, newest first.
---
---@return table[]
function M.list()
	M.cleanup()

	local sessions = {}
	for index = #state.codex_session_order, 1, -1 do
		local session = session_for_buffer(state.codex_session_order[index])
		if session_is_running(session) then
			table.insert(sessions, session)
		end
	end

	return sessions
end

---@param bufnr integer
---@return table|nil
function M.session(bufnr)
	return session_for_buffer(bufnr)
end

---@param session table|integer|nil
---@return string
function M.display_title(session)
	if type(session) ~= "table" then
		session = session_for_buffer(session)
	end
	if not session then
		return "Codex chat"
	end

	local title = session.title and session.title ~= "" and session.title or ("Chat #" .. session.id)
	if session.title_status == "naming" then
		return title .. " (naming...)"
	end
	if session.title_status == "failed" then
		return title .. " (title failed)"
	end

	return title
end

---Stores the current non-Codex buffer as the previous buffer to return to later.
function M.remember_previous_buffer()
	local current = vim.api.nvim_get_current_buf()
	if util.is_valid_buffer(current) and not util.is_codex_buffer(current) then
		state.previous_buf = current
	end
end

---Finds a fallback buffer to switch back to when the previous buffer is unavailable.
local function find_fallback_buffer()
	local alternate = vim.fn.bufnr("#")
	if alternate > 0 and util.is_valid_buffer(alternate) and not util.is_codex_buffer(alternate) then
		return alternate
	end

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if not util.is_codex_buffer(bufnr) and vim.bo[bufnr].buflisted and vim.api.nvim_buf_is_loaded(bufnr) then
			return bufnr
		end
	end

	return nil
end

---Switches the current window to the previously focused buffer, or a fallback buffer.
function M.switch_to_previous_buffer()
	if util.is_valid_buffer(state.previous_buf) and not util.is_codex_buffer(state.previous_buf) then
		vim.api.nvim_set_current_buf(state.previous_buf)
		return
	end

	local fallback = find_fallback_buffer()
	if fallback then
		vim.api.nvim_set_current_buf(fallback)
	end
end

---Makes a live Codex buffer the active send target.
---
---@param bufnr integer
---@return boolean
function M.activate_buffer(bufnr)
	local session = session_for_buffer(bufnr)
	if not session_is_running(session) then
		return false
	end

	session.last_active_at = os.time()
	sync_active_state(session)
	return true
end

local function title_slug(title)
	local slug = tostring(title or ""):lower()
	slug = slug:gsub("[^a-z0-9]+", "-"):gsub("^-+", ""):gsub("-+$", "")
	if slug == "" then
		return "chat"
	end

	return slug:sub(1, 48):gsub("-+$", "")
end

local function clean_title(title)
	title = tostring(title or ""):gsub("[%c\r\n]+", " ")
	title = title:gsub("^%s*#+%s*", "")
	title = title:gsub("^%s*[Tt]itle:%s*", "")
	title = title:gsub("^%s*[\"'`]+", "")
	title = title:gsub("[\"'`]+%s*$", "")
	title = util.trim_whitespace(title):gsub("%s+", " ")
	if #title > 48 then
		title = util.trim_whitespace(title:sub(1, 48):gsub("%s+%S*$", ""))
	end

	return title
end

local function codex_buffer_name(id, title)
	if title and title ~= "" then
		return constants.CODEX_BUF_NAME .. "/" .. id .. "/" .. title_slug(title)
	end

	return constants.CODEX_BUF_NAME .. "/" .. id
end

---@param bufnr integer
---@param title string
---@return boolean
function M.set_title(bufnr, title)
	local session = session_for_buffer(bufnr)
	title = clean_title(title)
	if not session or title == "" or not util.is_valid_buffer(session.bufnr) then
		return false
	end

	session.title = title
	session.title_status = nil
	session.title_error = nil
	vim.b[session.bufnr].codex_title = title
	pcall(vim.api.nvim_buf_set_name, session.bufnr, codex_buffer_name(session.id, title))
	return true
end

local function recent_scrollback(bufnr, max_lines)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	if #lines > max_lines then
		local trimmed = {}
		for index = #lines - max_lines + 1, #lines do
			table.insert(trimmed, lines[index])
		end
		lines = trimmed
	end

	return lines
end

local function has_content(lines)
	for _, line in ipairs(lines) do
		if util.trim_whitespace(line) ~= "" then
			return true
		end
	end

	return false
end

local function title_prompt(session, lines)
	return table.concat({
		"Generate a short descriptive title for this Codex chat.",
		"Output only the title.",
		"Use 2 to 6 words.",
		"Use plain ASCII.",
		"Do not use quotes, markdown, trailing punctuation, or explanations.",
		"",
		"Workspace: " .. (session.cwd or ""),
		"",
		"Recent terminal scrollback:",
		"```",
		table.concat(lines, "\n"),
		"```",
	}, "\n")
end

local function collect_job_data(target, data)
	if not data then
		return
	end

	for _, line in ipairs(data) do
		if line ~= "" then
			table.insert(target, line)
		end
	end
end

local function title_from_output(output_path, stdout_lines)
	local lines = {}
	if vim.fn.filereadable(output_path) == 1 then
		lines = vim.fn.readfile(output_path)
	else
		lines = stdout_lines
	end

	return clean_title(table.concat(lines, "\n"))
end

---@param bufnr integer
---@return boolean
function M.generate_title(bufnr)
	if vim.fn.executable("codex") ~= 1 then
		util.notify("codex executable was not found on PATH", vim.log.levels.ERROR)
		return false
	end

	local session = session_for_buffer(bufnr)
	if not session_is_running(session) then
		util.notify("Codex target buffer is not live", vim.log.levels.WARN)
		return false
	end
	if session.title_status == "naming" then
		util.notify("Codex chat title is already being generated", vim.log.levels.WARN)
		return false
	end

	local lines = recent_scrollback(session.bufnr, 200)
	if not has_content(lines) then
		util.notify("No Codex scrollback to name", vim.log.levels.WARN)
		return false
	end

	local output_path = vim.fn.tempname()
	local stdout_lines = {}
	local stderr_lines = {}
	local job_id = vim.fn.jobstart({
		"codex",
		"exec",
		"--ephemeral",
		"--sandbox",
		"read-only",
		"-c",
		'approval_policy="never"',
		"--cd",
		session.cwd,
		"--skip-git-repo-check",
		"--output-last-message",
		output_path,
		"-",
	}, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			collect_job_data(stdout_lines, data)
		end,
		on_stderr = function(_, data)
			collect_job_data(stderr_lines, data)
		end,
		on_exit = function(exited_job_id, code)
			vim.schedule(function()
				local current = state.codex_sessions[bufnr]
				if not current or current.title_job_id ~= exited_job_id then
					pcall(vim.fn.delete, output_path)
					return
				end

				current.title_job_id = nil
				current.title_output_path = nil
				if code == 0 then
					local title = title_from_output(output_path, stdout_lines)
					if M.set_title(bufnr, title) then
						util.notify("Named Codex chat: " .. title)
					else
						current.title_status = "failed"
						current.title_error = "empty title"
						util.notify("Codex title generation returned no title", vim.log.levels.WARN)
					end
				else
					current.title_status = "failed"
					current.title_error = table.concat(stderr_lines, "\n")
					util.notify("Failed to name Codex chat", vim.log.levels.WARN)
				end

				pcall(vim.fn.delete, output_path)
				refresh_chat_panel()
			end)
		end,
	})

	if job_id <= 0 then
		pcall(vim.fn.delete, output_path)
		util.notify("Failed to start Codex title job", vim.log.levels.ERROR)
		return false
	end

	session.title_status = "naming"
	session.title_error = nil
	session.title_job_id = job_id
	session.title_output_path = output_path
	vim.fn.chansend(job_id, title_prompt(session, lines))
	vim.fn.chanclose(job_id, "stdin")
	refresh_chat_panel()
	return true
end

---Starts a new Codex terminal buffer and begins the interactive session.
---
---@return table|nil session when Codex starts successfully.
function M.create()
	if vim.fn.executable("codex") ~= 1 then
		util.notify("codex executable was not found on PATH", vim.log.levels.ERROR)
		return nil
	end

	M.cleanup()
	M.remember_previous_buffer()
	vim.cmd("enew")

	local buf = vim.api.nvim_get_current_buf()
	local id = state.next_codex_session_id
	state.next_codex_session_id = id + 1

	local session = {
		id = id,
		bufnr = buf,
		cwd = vim.fn.getcwd(),
		started_at = os.time(),
		job_id = nil,
		exited = false,
		exit_code = nil,
	}

	state.codex_sessions[buf] = session
	append_to_order(buf)

	vim.bo[buf].buflisted = true
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "codex"
	vim.b[buf].codex_chat = true
	vim.b[buf].codex_session_id = id
	vim.b[buf].codex_cwd = session.cwd
	vim.b[buf].codex_started_at = session.started_at

	local term_buf = buf
	local job_id = vim.fn.jobstart({ "codex", "--cd", session.cwd }, {
		term = true,
		on_exit = function(exited_job_id, code)
			if state.codex_deleted_jobs[exited_job_id] then
				state.codex_deleted_jobs[exited_job_id] = nil
				return
			end

			local exited_session = state.codex_sessions[term_buf]
			if exited_session and exited_session.job_id == exited_job_id then
				exited_session.exited = true
				exited_session.exit_code = code
				exited_session.job_id = nil
			end

			if state.codex_active_buf == term_buf then
				sync_active_state(nil)
			end

			vim.schedule(function()
				if util.is_valid_buffer(term_buf) then
					vim.b[term_buf].codex_exited = true
					vim.b[term_buf].codex_exit_code = code
				end
				util.notify(
					"Codex chat #" .. id .. " exited with code " .. code,
					code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
				)
			end)
		end,
	})

	if job_id <= 0 then
		remove_session(buf, { delete_buffer = true })
		util.notify("Failed to start Codex chat", vim.log.levels.ERROR)
		return nil
	end

	session.job_id = job_id
	vim.api.nvim_buf_set_name(buf, codex_buffer_name(id))
	vim.bo[buf].filetype = "codex"
	vim.b[buf].codex_job_id = job_id
	M.activate_buffer(buf)
	vim.cmd("startinsert")
	return session
end

---@param bufnr integer
---@return boolean
function M.delete_buffer(bufnr)
	local session = session_for_buffer(bufnr)
	if not session then
		util.notify("Codex chat buffer not found", vim.log.levels.WARN)
		return false
	end

	local was_active = state.codex_active_buf == session.bufnr
	if session.job_id and session_is_running(session) then
		state.codex_deleted_jobs[session.job_id] = true
		pcall(vim.fn.jobstop, session.job_id)
	end
	remove_session(session.bufnr, { delete_buffer = true })

	if was_active then
		local replacement = newest_live_session()
		sync_active_state(replacement)
	end

	return true
end

---Compatibility wrapper for callers expecting a boolean start result.
---
---@return boolean true when Codex starts successfully, false when it fails.
function M.start()
	return M.create() ~= nil
end

---Creates a new Codex chat buffer and focuses it.
---
---@return boolean true when Codex starts successfully, false when it fails.
function M.new()
	return M.start()
end

---Ensures a running Codex chat buffer exists, starting it if needed.
---
---@return boolean true when a live Codex session is available.
function M.ensure()
	if M.active_session() then
		return true
	end

	return M.start()
end

---Sends text to a Codex terminal session.
---
---@param text string text to paste into Codex
---@param opts? {bufnr?: integer} target options
---@return boolean true when payload was sent.
function M.paste(text, opts)
	opts = opts or {}

	local session
	if opts.bufnr then
		session = session_for_buffer(opts.bufnr)
		if not session_is_running(session) then
			util.notify("Codex target buffer is not live", vim.log.levels.WARN)
			return false
		end
	else
		session = M.active_session()
		if not session then
			session = M.create()
		end
	end

	if not session_is_running(session) then
		return false
	end

	local payload = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	vim.api.nvim_chan_send(session.job_id, "\027[200~" .. payload .. "\027[201~\r")
	return true
end

---Focuses a live Codex chat buffer and makes it the active send target.
---
---@param bufnr integer
---@return boolean
function M.focus(bufnr)
	M.cleanup()

	local session = session_for_buffer(bufnr)
	if not session_is_running(session) then
		util.notify("Codex target buffer is not live", vim.log.levels.WARN)
		return false
	end

	M.remember_previous_buffer()
	M.activate_buffer(bufnr)
	vim.api.nvim_set_current_buf(bufnr)
	vim.cmd("startinsert")
	return true
end

---Toggles focus between the current buffer and the active Codex chat buffer.
function M.toggle()
	if util.is_codex_buffer(vim.api.nvim_get_current_buf()) then
		M.switch_to_previous_buffer()
		return
	end

	M.remember_previous_buffer()
	local session = M.active_session()
	if session then
		vim.api.nvim_set_current_buf(session.bufnr)
		vim.cmd("startinsert")
		return
	end

	M.create()
end

return M
