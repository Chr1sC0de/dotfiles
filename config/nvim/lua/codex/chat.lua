local constants = require("codex.constants")
local state = require("codex.state")
local util = require("codex.util")

--- Utility functions for launching and interacting with the Codex terminal chat buffer.
local M = {}

---Returns true when the codex job is active.
---
---@return boolean
function M.is_running()
	return state.codex_job_id ~= nil and vim.fn.jobwait({ state.codex_job_id }, 0)[1] == -1
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
		if bufnr ~= state.codex_buf and vim.bo[bufnr].buflisted and vim.api.nvim_buf_is_loaded(bufnr) then
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

---Starts a new Codex terminal buffer and begins the interactive session.
---
---@return boolean true when Codex starts successfully, false when it fails.
function M.start()
	if vim.fn.executable("codex") ~= 1 then
		util.notify("codex executable was not found on PATH", vim.log.levels.ERROR)
		return false
	end

	if util.is_valid_buffer(state.codex_buf) then
		pcall(vim.api.nvim_buf_delete, state.codex_buf, { force = true })
	end

	M.remember_previous_buffer()
	vim.cmd("enew")

	local buf = vim.api.nvim_get_current_buf()
	state.codex_buf = buf

	vim.api.nvim_buf_set_name(buf, constants.CODEX_BUF_NAME)
	vim.bo[buf].buflisted = true
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "codex"
	vim.b[buf].codex_chat = true
	vim.b[buf].codex_cwd = vim.fn.getcwd()

	local term_buf = buf
	state.codex_job_id = vim.fn.jobstart({ "codex", "--cd", vim.fn.getcwd() }, {
		term = true,
		on_exit = function(job_id, code)
			if state.codex_job_id == job_id then
				state.codex_job_id = nil
			end

			vim.schedule(function()
				if util.is_valid_buffer(term_buf) then
					vim.b[term_buf].codex_exited = true
				end
				util.notify(
					"Codex chat exited with code " .. code,
					code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
				)
			end)
		end,
	})

	vim.cmd("startinsert")
	return true
end

---Ensures a running Codex chat buffer exists, starting it if needed.
---
---@return boolean true when a live Codex session is available.
function M.ensure()
	if util.is_valid_buffer(state.codex_buf) and M.is_running() then
		return true
	end

	return M.start()
end

---Sends text to the active Codex terminal session.
---
---@param text string text to paste into Codex
---@return boolean true when payload was sent.
function M.paste(text)
	if not M.ensure() or not M.is_running() then
		return false
	end

	local payload = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	vim.api.nvim_chan_send(state.codex_job_id, "\027[200~" .. payload .. "\027[201~\r")
	return true
end

---Toggles focus between the current buffer and the Codex chat buffer.
function M.toggle()
	if util.is_codex_buffer(vim.api.nvim_get_current_buf()) then
		M.switch_to_previous_buffer()
		return
	end

	M.remember_previous_buffer()
	if M.ensure() then
		vim.api.nvim_set_current_buf(state.codex_buf)
		vim.cmd("startinsert")
	end
end

return M
