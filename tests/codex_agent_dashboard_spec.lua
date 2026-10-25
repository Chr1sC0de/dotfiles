vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local chat = require("codex.chat")
local herdr = require("codex.herdr")
local navigation = require("workmux.herdr")
local dashboard = require("codex.agent_dashboard")
local function equal(a, b)
	assert(vim.deep_equal(a, b), vim.inspect(a) .. " != " .. vim.inspect(b))
end
local external = {
	name = "external",
	agent = "codex",
	agent_pane_id = "w1:p1",
	status = "working",
	agent_cwd = "/other",
	tab_label = "main",
	raw_agent = {},
}
local managed = {
	name = "managed",
	agent = "codex",
	agent_pane_id = "w2:p1",
	status = "idle",
	agent_cwd = "/project",
	tab_label = "main",
	raw_agent = { name = "managed" },
}
local sessions = {}
chat.list = function()
	return sessions
end
chat.is_running = function(buf)
	return buf == 42
end
chat.ipc_status_label = function()
	return "SEEN"
end
herdr.available = function()
	return true
end
herdr.launch_metadata = function(agent)
	if agent.name == "managed" then
		return { tandem_configured = true }
	end
end
local connected = true
package.loaded.tandem = {
	status = function()
		return { connected = connected, root = "/project" }
	end,
}
equal({ dashboard._test.item_status(external) }, { "No", "Unknown", "—" })
equal({ dashboard._test.item_status(managed) }, { "No", "Configured", "—" })
sessions = { { bufnr = 42, herdr_agent_name = "external", herdr_pane_id = "w1:p1", external_attachment = true } }
equal({ dashboard._test.item_status(external) }, { "Yes", "Unknown", "Unavailable" })
local callback
navigation.agent_snapshot = function(cb)
	callback = cb
end
dashboard.open()
callback({ managed, external })
local win = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_get_current_buf()
local function lines()
	return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
assert(lines():find("Editor Tandem: connected", 1, true))
vim.api.nvim_win_set_cursor(win, { 8, 0 })
equal(dashboard._test.selected().name, "managed")
dashboard.refresh()
callback({ external, managed })
equal(dashboard._test.selected().name, "managed")
dashboard.refresh()
callback(nil, "offline")
assert(lines():find("STALE: offline", 1, true))
equal(dashboard._test.selected().name, "managed")
connected = false
dashboard._test.render()
assert(lines():find("Editor Tandem: disconnected", 1, true))
local detached
chat.detach = function(bufnr)
	detached = bufnr
	sessions = {}
	return true
end
vim.api.nvim_win_set_cursor(win, { 7, 0 })
dashboard._test.detach()
equal(detached, 42)
local pending = callback
dashboard.close()
pending({}) -- A late response must not recreate the closed dashboard.
equal(vim.api.nvim_win_is_valid(win), false)
dashboard.open()
callback({ external })
local attach_target
chat.attach_agent = function(target)
	attach_target = target
end
local enter = vim.fn.maparg("<CR>", "n", false, true).callback
enter()
equal(attach_target, "external")
dashboard.close()
local api = require("codex")
require("codex.commands").setup(api)
equal(vim.fn.maparg("<leader>aA", "n", false, true).callback, api.attach_chat)
equal(vim.fn.exists(":AgentDashboard"), 2)
equal(vim.fn.exists(":CodexChatAttach"), 2)
print("codex_agent_dashboard_spec.lua: ok")
