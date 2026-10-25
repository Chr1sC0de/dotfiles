local chat = require("codex.chat")
local herdr = require("codex.herdr")
local navigation = require("workmux.herdr")
local util = require("codex.util")

local M = {}
local buffer, window, timer
local items, rows = {}, {}
local generation, loading, failure = 0, false, nil

local function identity(item)
	return item.name or item.agent_pane_id
end

local function local_session(item)
	for _, session in ipairs(chat.list()) do
		if session.herdr_agent_name == identity(item) and session.herdr_pane_id == item.agent_pane_id then
			return session
		end
	end
end

local function selected()
	if not util.is_valid_window(window) then
		return nil
	end
	return rows[vim.api.nvim_win_get_cursor(window)[1]]
end

local function connection_label()
	local ok, tandem = pcall(require, "tandem")
	if not ok or type(tandem.status) ~= "function" then
		return "Editor Tandem: unavailable"
	end
	local status = tandem.status()
	return "Editor Tandem: "
		.. (status.connected and "connected" or "disconnected")
		.. "  Project: "
		.. (status.root or "unknown")
end

local function item_status(item)
	local session = local_session(item)
	local attached = session ~= nil and chat.is_running(session.bufnr)
	local record = herdr.launch_metadata(item.raw_agent or {})
	local configured = record ~= nil or (session and session.tandem_configured == true)
	local hooks = session and chat.ipc_status_label(session) or "—"
	if session and session.external_attachment then
		hooks = "Unavailable"
	end
	return attached and "Yes" or "No", configured and "Configured" or "Unknown", hooks
end

local function render()
	if not util.is_valid_buffer(buffer) or not util.is_valid_window(window) then
		return
	end
	local current = selected()
	local key = current and identity(current)
	local previous_line = vim.api.nvim_win_get_cursor(window)[1]
	local lines = {
		"Agent Attachments — this Neovim",
		connection_label(),
		"Enter attach/open · d detach · o go to agent · r refresh · q close",
		"Tandem shows launch configuration, not a live per-agent connection.",
		failure and ("STALE: " .. failure) or (loading and "Refreshing…" or ""),
		string.format("%-25s %-10s %-8s %-12s %-12s %s", "Agent", "Task", "Here", "Tandem", "Hooks", "Project / tab"),
	}
	rows = {}
	local selected_line
	for _, item in ipairs(items) do
		local attached, tandem, hooks = item_status(item)
		lines[#lines + 1] = string.format(
			"%-25s %-10s %-8s %-12s %-12s %s / %s",
			util.trim_display(identity(item), 25),
			item.status or "unknown",
			attached,
			tandem,
			hooks,
			vim.fn.fnamemodify(item.agent_cwd or "", ":~"),
			item.tab_label or ""
		)
		rows[#lines] = item
		if identity(item) == key then
			selected_line = #lines
		end
	end
	if #items == 0 then
		lines[#lines + 1] = "No agents found."
	end
	vim.bo[buffer].modifiable = true
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
	vim.bo[buffer].modifiable = false
	if #items > 0 then
		vim.api.nvim_win_set_cursor(window, { selected_line or math.max(7, math.min(previous_line, #lines)), 0 })
	end
end

function M.refresh()
	if loading or not util.is_valid_window(window) then
		return
	end
	if not herdr.available() then
		failure = "Herdr is unavailable in this Neovim session"
		render()
		return
	end
	loading = true
	local request = generation
	render()
	navigation.agent_snapshot(function(updated, err)
		if request ~= generation or not util.is_valid_window(window) then
			return
		end
		loading = false
		failure = err
		if updated then
			items = updated
			table.sort(items, function(a, b)
				return identity(a) < identity(b)
			end)
		end
		render()
	end)
end

local function stop_refresh()
	generation = generation + 1
	loading = false
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
end

function M.close()
	stop_refresh()
	if util.is_valid_window(window) then
		vim.api.nvim_win_close(window, true)
	end
	window = nil
end

local function open_selected()
	local item = selected()
	if not item then
		return
	end
	M.close()
	if item.agent == "codex" then
		chat.attach_agent(identity(item))
	else
		navigation.focus_agent_item(item)
	end
end

local function detach_selected()
	local item = selected()
	local session = item and local_session(item)
	if not session then
		util.notify("This agent is not attached here")
		return
	end
	chat.detach(session.bufnr)
	render()
	M.refresh()
end

local function navigate_selected()
	local item = selected()
	if not item then
		return
	end
	M.close()
	navigation.focus_agent_item(item)
end

function M.open()
	if util.is_valid_window(window) then
		vim.api.nvim_set_current_win(window)
		M.refresh()
		return
	end
	if not util.is_valid_buffer(buffer) then
		buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buffer, "codex://agent-dashboard")
		vim.bo[buffer].buftype = "nofile"
		vim.bo[buffer].bufhidden = "hide"
		vim.bo[buffer].swapfile = false
		vim.bo[buffer].filetype = "codexagents"
		local opts = { buffer = buffer, silent = true, nowait = true }
		vim.keymap.set("n", "<CR>", open_selected, opts)
		vim.keymap.set("n", "d", detach_selected, opts)
		vim.keymap.set("n", "o", navigate_selected, opts)
		vim.keymap.set("n", "r", M.refresh, opts)
		vim.keymap.set("n", "q", M.close, opts)
		vim.keymap.set("n", "<Esc>", M.close, opts)
	end
	local width = math.max(1, math.min(math.floor(vim.o.columns * 0.94), vim.o.columns - 2))
	local height = math.max(1, math.min(math.floor(vim.o.lines * 0.7), vim.o.lines - 4))
	window = vim.api.nvim_open_win(buffer, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(0, math.floor((vim.o.lines - height) / 2)),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		style = "minimal",
		border = "rounded",
		title = " Agent Attachments ",
		title_pos = "center",
	})
	vim.wo[window].cursorline = true
	vim.wo[window].wrap = false
	vim.api.nvim_create_autocmd("WinClosed", { pattern = tostring(window), once = true, callback = stop_refresh })
	failure = nil
	render()
	M.refresh()
	timer = vim.uv.new_timer()
	timer:start(2000, 2000, vim.schedule_wrap(M.refresh))
end

M._test = { item_status = item_status, render = render, selected = selected, detach = detach_selected }
return M
