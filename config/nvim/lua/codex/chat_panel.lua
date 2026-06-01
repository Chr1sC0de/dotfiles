local chat = require("codex.chat")
local constants = require("codex.constants")
local state = require("codex.state")
local util = require("codex.util")

local M = {}

function M.close_preview()
	if util.is_valid_window(state.codex_chat_preview_win) then
		vim.api.nvim_win_close(state.codex_chat_preview_win, true)
	end
	state.codex_chat_preview_win = nil
end

function M.close()
	if util.is_valid_window(state.codex_chat_buffers_win) then
		vim.api.nvim_win_close(state.codex_chat_buffers_win, true)
	end
	state.codex_chat_buffers_win = nil
	M.close_preview()
end

function M.selected()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local bufnr = state.codex_chat_line_to_buf[line]
	if not bufnr then
		return nil
	end

	return bufnr
end

local function open_selected_chat()
	local bufnr = M.selected()
	if not bufnr then
		return
	end

	M.close()
	chat.focus(bufnr)
end

local function switch_selected_chat_target()
	local bufnr = M.selected()
	local session = chat.session(bufnr)
	if not session then
		util.notify("No Codex chat buffer under cursor", vim.log.levels.WARN)
		return
	end

	if chat.activate_buffer(bufnr) then
		util.notify("Active Codex target: " .. chat.display_title(session))
		M.close()
	end
end

local function create_chat()
	M.close()
	chat.new()
end

local function delete_selected_chat()
	local bufnr = M.selected()
	local session = chat.session(bufnr)
	if not session then
		util.notify("No Codex chat buffer under cursor", vim.log.levels.WARN)
		return
	end

	local label = chat.display_title(session)
	vim.ui.input({ prompt = "Type `delete` to delete " .. label .. ": " }, function(value)
		if value == nil then
			return
		end
		if value ~= "delete" then
			util.notify("Codex chat delete cancelled", vim.log.levels.WARN)
			return
		end

		if chat.delete_buffer(bufnr) then
			util.notify("Deleted Codex chat: " .. label)
			M.refresh_open()
		end
	end)
end

local function title_selected_chat()
	local bufnr = M.selected()
	if not bufnr then
		util.notify("No Codex chat buffer under cursor", vim.log.levels.WARN)
		return
	end

	if chat.generate_title(bufnr) then
		M.refresh_open()
	end
end

local function resync_selected_chat()
	local bufnr = M.selected()
	if not bufnr then
		util.notify("No Codex chat buffer under cursor", vim.log.levels.WARN)
		return
	end

	chat.resync(bufnr)
	M.refresh_open()
end

local function preview_chat(bufnr)
	if not bufnr or not util.is_valid_buffer(bufnr) then
		util.notify("No Codex chat buffer under cursor", vim.log.levels.WARN)
		return
	end

	local session = nil
	for _, candidate in ipairs(chat.list()) do
		if candidate.bufnr == bufnr then
			session = candidate
			break
		end
	end
	if not util.is_valid_buffer(bufnr) then
		util.notify("Codex target buffer is not live", vim.log.levels.WARN)
		return
	end

	M.close_preview()

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local max_lines = 200
	if #lines > max_lines then
		local start = #lines - max_lines + 1
		local trimmed = {}
		for index = start, #lines do
			table.insert(trimmed, lines[index])
		end
		lines = trimmed
	end

	if #lines == 0 then
		lines = { "[No Codex scrollback]" }
	end

	local title = " Codex Chat"
	if session then
		title = title .. " #" .. session.id
	end
	title = title .. " "

	local preview_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[preview_buf].bufhidden = "wipe"
	vim.bo[preview_buf].buftype = "nofile"
	vim.bo[preview_buf].filetype = "codex"
	vim.bo[preview_buf].modifiable = true
	vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
	vim.bo[preview_buf].modifiable = false
	vim.bo[preview_buf].swapfile = false

	local columns = vim.o.columns
	local editor_lines = vim.o.lines
	local width = math.min(math.max(math.floor(columns * 0.72), 60), math.max(columns - 6, 20))
	local height = math.min(math.max(#lines, 12), math.max(editor_lines - 8, 8))
	state.codex_chat_preview_win = vim.api.nvim_open_win(preview_buf, true, {
		relative = "editor",
		row = math.max(math.floor((editor_lines - height) / 2), 0),
		col = math.max(math.floor((columns - width) / 2), 0),
		width = width,
		height = height,
		border = "rounded",
		style = "minimal",
		title = title,
		title_pos = "center",
	})
	vim.wo[state.codex_chat_preview_win].number = false
	vim.wo[state.codex_chat_preview_win].relativenumber = false
	vim.wo[state.codex_chat_preview_win].signcolumn = "no"
	vim.wo[state.codex_chat_preview_win].wrap = true

	local opts = { buffer = preview_buf, nowait = true, silent = true }
	vim.keymap.set("n", "q", M.close_preview, opts)
	vim.keymap.set("n", "<Esc>", M.close_preview, opts)
end

local function preview_selected_chat()
	preview_chat(M.selected())
end

local function ensure_chat_buffers_buffer()
	if util.is_valid_buffer(state.codex_chat_buffers_buf) then
		return state.codex_chat_buffers_buf
	end

	local existing = vim.fn.bufnr(constants.CODEX_CHAT_BUFFERS_BUF_NAME)
	if existing > 0 and util.is_valid_buffer(existing) then
		state.codex_chat_buffers_buf = existing
	else
		state.codex_chat_buffers_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(state.codex_chat_buffers_buf, constants.CODEX_CHAT_BUFFERS_BUF_NAME)
	end

	vim.bo[state.codex_chat_buffers_buf].bufhidden = "hide"
	vim.bo[state.codex_chat_buffers_buf].buftype = "nofile"
	vim.bo[state.codex_chat_buffers_buf].filetype = "codexbuffers"
	vim.bo[state.codex_chat_buffers_buf].modifiable = false
	vim.bo[state.codex_chat_buffers_buf].swapfile = false

	local opts = { buffer = state.codex_chat_buffers_buf, nowait = true, silent = true }
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
	vim.keymap.set("n", "r", M.refresh_open, opts)
	vim.keymap.set("n", "R", resync_selected_chat, opts)
	vim.keymap.set("n", "<CR>", open_selected_chat, opts)
	vim.keymap.set("n", "s", switch_selected_chat_target, opts)
	vim.keymap.set("n", "n", create_chat, opts)
	vim.keymap.set("n", "d", delete_selected_chat, opts)
	vim.keymap.set("n", "t", title_selected_chat, opts)
	vim.keymap.set("n", "p", preview_selected_chat, opts)

	return state.codex_chat_buffers_buf
end

local function session_age(session)
	return math.max(os.time() - (session.started_at or os.time()), 0) .. "s"
end

local function session_cwd(session)
	return vim.fn.fnamemodify(session.cwd or "", ":~:.")
end

local function build_chat_buffers_lines()
	local lines = {
		"Codex Chat Buffers",
		"",
		"Keys: <CR> open  s switch  n new  d delete  t title  p preview  r refresh  R resync  q close",
		"",
	}
	state.codex_chat_line_to_buf = {}
	state.codex_chat_line_highlights = {
		[1] = "Title",
		[3] = "Comment",
	}

	local sessions = chat.list()
	if #sessions == 0 then
		table.insert(lines, "No Codex chat buffers. Press n to create one.")
		state.codex_chat_line_highlights[#lines] = "Comment"
		return lines
	end

	table.insert(
		lines,
		string.format(
			"%-4s %-6s %-7s %-6s %-6s %-8s %-30s %-28s %s",
			"ID",
			"Status",
			"IPC",
			"Active",
			"Buffer",
			"Age",
			"Title",
			"CWD",
			"Name"
		)
	)
	state.codex_chat_line_highlights[#lines] = "Type"

	local active_buf = chat.active_bufnr()
	for _, session in ipairs(sessions) do
		local name = vim.api.nvim_buf_get_name(session.bufnr)
		local active = session.bufnr == active_buf and "yes" or ""
		local status = chat.task_status_label(session)
		local ipc = chat.ipc_status_label(session)
		local line = string.format(
			"%-4d %-6s %-7s %-6s %-6d %-8s %-30s %-28s %s",
			session.id,
			status,
			ipc,
			active,
			session.bufnr,
			session_age(session),
			util.trim_display(chat.display_title(session), 30),
			util.trim_display(session_cwd(session), 28),
			util.trim_display(name, 42)
		)
		table.insert(lines, line)
		state.codex_chat_line_to_buf[#lines] = session.bufnr
		state.codex_chat_line_highlights[#lines] = chat.task_status_highlight(session)
	end

	return lines
end

local function first_selectable_chat_line()
	local first_line = nil
	for line, bufnr in pairs(state.codex_chat_line_to_buf) do
		if bufnr and (not first_line or line < first_line) then
			first_line = line
		end
	end

	return first_line
end

local function focus_first_selectable_chat_line()
	if not util.is_valid_window(state.codex_chat_buffers_win) then
		return
	end

	local line = first_selectable_chat_line()
	if not line then
		return
	end

	pcall(vim.api.nvim_win_set_cursor, state.codex_chat_buffers_win, { line, 0 })
end

local function chat_buffers_float_config()
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
		title = " Codex Chat Buffers ",
		title_pos = "center",
	}
end

function M.render()
	if not util.is_valid_buffer(state.codex_chat_buffers_buf) then
		return
	end

	local lines = build_chat_buffers_lines()
	vim.bo[state.codex_chat_buffers_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.codex_chat_buffers_buf, 0, -1, false, lines)
	vim.bo[state.codex_chat_buffers_buf].modified = false
	vim.bo[state.codex_chat_buffers_buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(
		state.codex_chat_buffers_buf,
		constants.CODEX_CHAT_BUFFERS_HIGHLIGHT_NAMESPACE,
		0,
		-1
	)

	for line, highlight in pairs(state.codex_chat_line_highlights) do
		vim.api.nvim_buf_add_highlight(
			state.codex_chat_buffers_buf,
			constants.CODEX_CHAT_BUFFERS_HIGHLIGHT_NAMESPACE,
			highlight,
			line - 1,
			0,
			-1
		)
	end

	if util.is_valid_window(state.codex_chat_buffers_win) then
		vim.api.nvim_win_set_config(state.codex_chat_buffers_win, chat_buffers_float_config())
	end
end

function M.refresh_open()
	if util.is_valid_buffer(state.codex_chat_buffers_buf) then
		M.render()
	end
end

function M.open()
	local bufnr = ensure_chat_buffers_buffer()
	if util.is_valid_window(state.codex_chat_buffers_win) then
		vim.api.nvim_set_current_win(state.codex_chat_buffers_win)
		M.render()
		return
	end

	state.codex_chat_buffers_win = vim.api.nvim_open_win(bufnr, true, chat_buffers_float_config())
	vim.wo[state.codex_chat_buffers_win].cursorline = true
	vim.wo[state.codex_chat_buffers_win].number = false
	vim.wo[state.codex_chat_buffers_win].relativenumber = false
	vim.wo[state.codex_chat_buffers_win].signcolumn = "no"
	vim.wo[state.codex_chat_buffers_win].wrap = false
	M.render()
	focus_first_selectable_chat_line()
end

function M.toggle()
	if util.is_valid_window(state.codex_chat_buffers_win) then
		M.close()
		return
	end

	M.open()
end

return M
