local constants = require("codex.constants")
local state = require("codex.state")
local util = require("codex.util")

local M = {}

local function ephemeral_spinner_style(action)
	return constants.EPHEMERAL_SPINNER_STYLES[action] or constants.EPHEMERAL_SPINNER_STYLES.command
end

local function ephemeral_running_label(action, target, job)
	local style = ephemeral_spinner_style(action)
	local job_id = job and " #" .. job.id or ""

	return "Codex" .. job_id .. " " .. style.verb .. " " .. target.kind
end

local function ephemeral_spinner_label(action, target, job)
	local instruction = util.job_instruction_display(job)
	if instruction == "" then
		return ephemeral_running_label(action, target, job)
	end

	local job_id = job and " #" .. job.id or ""
	return "Codex" .. job_id .. " " .. action .. ": " .. util.trim_display(instruction, 48)
end

function M.define_signs()
	for _, style in pairs(constants.EPHEMERAL_SPINNER_STYLES) do
		for _, sign in ipairs(style.frames) do
			vim.fn.sign_define(sign.name, { text = sign.text, texthl = style.highlight })
		end
	end
end

local function refresh_ephemeral_diagnostics(bufnr)
	if not util.is_valid_buffer(bufnr) then
		return
	end

	local diagnostics = {}
	for _, record in pairs(state.active_ephemeral_diagnostics) do
		if record.bufnr == bufnr then
			table.insert(diagnostics, record.diagnostic)
		end
	end

	vim.diagnostic.set(constants.EPHEMERAL_DIAGNOSTIC_NAMESPACE, bufnr, diagnostics, {})
end

function M.start_diagnostic(action, target, job)
	local bufnr = target.spinner_buf
	if not util.is_valid_buffer(bufnr) then
		return function() end
	end

	local id = state.next_ephemeral_diagnostic_id
	state.next_ephemeral_diagnostic_id = state.next_ephemeral_diagnostic_id + 1
	state.active_ephemeral_diagnostics[id] = {
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
		state.active_ephemeral_diagnostics[id] = nil
		refresh_ephemeral_diagnostics(bufnr)
	end
end

function M.start_spinner(action, target, job)
	local bufnr = target.spinner_buf
	if not util.is_valid_buffer(bufnr) then
		return function() end
	end

	local style = ephemeral_spinner_style(action)
	local sign_id = state.next_ephemeral_sign_id
	state.next_ephemeral_sign_id = state.next_ephemeral_sign_id + 1

	local timer = vim.uv.new_timer()
	local extmark_id = nil
	local frame = 1
	local running = true

	local function target_line()
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		return math.min(math.max(target.spinner_line, 1), math.max(line_count, 1))
	end

	local function place_sign()
		if not running or not util.is_valid_buffer(bufnr) then
			return
		end

		local line = target_line()
		local sign = style.frames[frame]
		vim.fn.sign_place(sign_id, constants.EPHEMERAL_SIGN_GROUP, sign.name, bufnr, {
			lnum = line,
			priority = 30,
		})

		local ok, next_extmark_id =
			pcall(vim.api.nvim_buf_set_extmark, bufnr, constants.EPHEMERAL_SPINNER_NAMESPACE, line - 1, 0, {
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

		if util.is_valid_buffer(bufnr) then
			vim.fn.sign_unplace(constants.EPHEMERAL_SIGN_GROUP, { buffer = bufnr, id = sign_id })
			if extmark_id then
				pcall(vim.api.nvim_buf_del_extmark, bufnr, constants.EPHEMERAL_SPINNER_NAMESPACE, extmark_id)
			end
		end
	end
end

return M
