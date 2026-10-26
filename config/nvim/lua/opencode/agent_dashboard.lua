local chat = require("opencode.chat")
local herdr = require("opencode.herdr")
local navigation = require("workmux.herdr")
local util = require("opencode.util")

local M = {}
local picker, timer
local items = {}
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
	return picker and not picker.closed and picker:current() or nil
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
	if not picker or picker.closed then
		return
	end
	picker.title = "Agent Attachments · " .. connection_label() .. (failure and (" · STALE: " .. failure) or "")
	for _, item in ipairs(items) do
		local attached, tandem, hooks = item_status(item)
		item.text = string.format(
			"%s  %s  Here:%s  Tandem:%s  Hooks:%s  %s / %s",
			identity(item),
			item.status or "unknown",
			attached,
			tandem,
			hooks,
			vim.fn.fnamemodify(item.agent_cwd or "", ":~"),
			item.tab_label or ""
		)
	end
	picker:refresh()
end

function M.refresh()
	if loading or not picker or picker.closed then
		return
	end
	if not herdr.available() then
		failure = "Herdr is unavailable in this Neovim session"
		render()
		return
	end
	loading = true
	local request = generation
	navigation.agent_snapshot(function(updated, err)
		if request ~= generation or not picker or picker.closed then
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
	if picker then
		picker:close()
	end
	picker = nil
end

local function open_selected()
	local item = selected()
	if not item then
		return
	end
	M.close()
	if item.agent == "opencode" then
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
	if picker and not picker.closed then
		picker:focus()
		M.refresh()
		return
	end
	failure = nil
	local keys = {
		d = { "detach_agent", mode = "n", desc = "Detach agent" },
		o = { "navigate_agent", mode = "n", desc = "Go to agent" },
		r = { "refresh_agents", mode = "n", desc = "Refresh agents" },
		q = { "close", mode = "n" },
	}
	local Snacks = _G.Snacks or require("snacks")
	picker = Snacks.picker.pick({
		title = "Agent Attachments",
		show_empty = true,
		finder = function()
			return items
		end,
		format = function(item)
			return { { item.text } }
		end,
		preview = navigation.preview_agent,
		confirm = open_selected,
		actions = {
			detach_agent = detach_selected,
			navigate_agent = navigate_selected,
			refresh_agents = M.refresh,
		},
		win = { input = { keys = keys }, list = { keys = keys } },
		on_close = stop_refresh,
	})
	render()
	M.refresh()
	timer = vim.uv.new_timer()
	timer:start(2000, 2000, vim.schedule_wrap(M.refresh))
end

M._test = { item_status = item_status, render = render, selected = selected, detach = detach_selected }
return M
