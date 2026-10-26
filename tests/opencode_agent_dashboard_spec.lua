vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
local Snacks = require("snacks")
Snacks.setup({ picker = { enabled = true } })
local chat = require("opencode.chat")
local herdr = require("opencode.herdr")
local navigation = require("workmux.herdr")
local dashboard = require("opencode.agent_dashboard")
local function equal(a, b)
	assert(vim.deep_equal(a, b), vim.inspect(a) .. " != " .. vim.inspect(b))
end
local external = {
	name = "external",
	agent = "opencode",
	agent_pane_id = "w1:p1",
	status = "working",
	agent_cwd = "/other",
	tab_label = "main",
	workspace_label = "workspace",
	raw_agent = {},
}
local managed = {
	name = "managed",
	agent = "opencode",
	agent_pane_id = "w2:p1",
	status = "idle",
	agent_cwd = "/project",
	tab_label = "main",
	workspace_label = "workspace",
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
local picker = Snacks.picker.get()[1]
local function settle()
	assert(vim.wait(1000, function()
		return not picker.finder:running() and not picker.matcher.task:running()
	end))
end
settle()
assert(picker.title:find("Editor Tandem: connected", 1, true))
equal(picker.opts.preview, navigation.preview_agent)
picker.list:move(2, true)
equal(dashboard._test.selected().name, "managed")
dashboard.refresh()
callback({ external, managed })
settle()
equal(dashboard._test.selected().name, "managed")
dashboard.refresh()
callback(nil, "offline")
settle()
assert(picker.title:find("STALE: offline", 1, true))
equal(dashboard._test.selected().name, "managed")
connected = false
dashboard._test.render()
settle()
assert(picker.title:find("Editor Tandem: disconnected", 1, true))
local detached
chat.detach = function(bufnr)
	detached = bufnr
	sessions = {}
	return true
end
picker.list:move(1, true)
dashboard._test.detach()
equal(detached, 42)
local pending = callback
dashboard.close()
pending({}) -- A late response must not recreate the closed dashboard.
equal(picker.closed, true)
dashboard.open()
callback({ external })
picker = Snacks.picker.get()[1]
settle()
local attach_target
chat.attach_agent = function(target)
	attach_target = target
end
picker.opts.confirm(picker, picker:current())
equal(attach_target, "external")
dashboard.close()
local api = require("opencode")
require("opencode.commands").setup(api)
equal(vim.fn.maparg("<leader>aA", "n", false, true).callback, api.attach_chat)
equal(vim.fn.exists(":AgentDashboard"), 2)
equal(vim.fn.exists(":OpenCodeChatAttach"), 2)
print("opencode_agent_dashboard_spec.lua: ok")
