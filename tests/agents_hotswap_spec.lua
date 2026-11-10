vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local original_stdpath, isolated = vim.fn.stdpath, vim.fn.tempname()
vim.fn.stdpath = function(kind)
	return kind == "state" and isolated or original_stdpath(kind)
end
dofile("tests/support/tandem.lua")
local selection = require("agents.selection")
local model = require("agents.ephemeral.model")
local catalog = require("agents.ephemeral.catalog")
local chat = require("agents.chat")
local herdr = require("agents.herdr")
local jobs = require("agents.ephemeral.jobs")
local project = selection.project()
vim.notify = function() end
vim.fn.executable = function()
	return 1
end
selection.set("pi")

-- Pi picker labels, catalog ownership, preference and actual launch routing.
local discover, picker, choose
catalog.fetch = function(callback, id)
	assert(id == "pi")
	discover = callback
	return function() end
end
vim.ui.select = function(items, opts, callback)
	picker, choose = { items = items, opts = opts }, callback
end
model.select("query")
discover({ { model = "fixture/pi-model", label = "Pi model" } }, "live")
assert(picker.opts.prompt:find("pi queries model", 1, true))
choose(picker.items[2])
assert(model.get("query", "pi") == "fixture/pi-model")
assert(model.get("query", "opencode") == nil)
local args = assert(
	jobs.command_args({ backend = "pi", action = "query", cwd = vim.fn.getcwd(), model = model.get("query", "pi") })
)
assert(args[1] == "pi" and args[vim.fn.index(args, "--model") + 2] == "fixture/pi-model")

-- A switch away and back cannot resurrect an old picker, even on the same ID.
model.select("query")
discover({}, "live")
local stale = choose
selection.set("opencode")
selection.set("pi")
stale(picker.items[1])
assert(model.get("query", "pi") == "fixture/pi-model")
model.select("query")
local original_project = selection.project
selection.project = function()
	return project .. "/other-project"
end
discover({}, "live")
selection.project = original_project
assert(model.get("query", "pi") == "fixture/pi-model")

-- Every legacy command has a neutral equivalent with the same options.
require("agents").setup()
assert(require("opencode") == require("agents"))
assert(require("config.opencode") == require("config.agents"))
local commands = vim.api.nvim_get_commands({})
for name, command in pairs(commands) do
	if name:match("^OpenCode") then
		local alias = assert(commands[name:gsub("^OpenCode", "Agent")], name)
		assert(alias.nargs == command.nargs and alias.range == command.range)
	end
end

-- Remember independent live identities, restore after switching and after all
-- local terminal clients are gone (the restart path), and reject stale panes.
local agents = {
	oc = { name = "oc", agent = "opencode", pane_id = "w1:p1", workspace_id = "w1" },
	pi = { name = "pi", agent = "pi", pane_id = "w1:p2", workspace_id = "w1" },
}
local attached = 0
herdr.available = function()
	return true
end
herdr.get_agent = function(name, callback)
	callback(agents[name])
end
herdr.attach = function()
	attached = attached + 1
	return 1000 + attached
end
herdr.prepare = function()
	error("external agents must not acquire routing")
end
herdr.close_pane = function()
	error("external panes must survive detach")
end
vim.fn.jobwait = function()
	return { -1 }
end
vim.fn.jobstop = function() end
chat.attach_agent("oc")
local oc = assert(chat.active_session())
chat.attach_agent("pi")
local pi = assert(chat.active_session())
assert(pi.backend == "pi" and oc.backend == "opencode")
assert(chat.switch_backend("opencode") and chat.active_session() == oc)
assert(chat.switch_backend("pi") and chat.active_session() == pi)
assert(attached == 2)
assert(chat.detach(pi.bufnr) and chat.detach(oc.bufnr))
package.loaded["agents.attachment"] = nil
assert(require("agents.attachment").load(project, "pi").pane_id == "w1:p2")
selection.set("opencode")
chat.toggle()
assert(chat.active_session().backend == "opencode")
assert(chat.switch_backend("pi") and chat.active_session().backend == "pi")
assert(attached == 4)
assert(chat.detach(chat.active_bufnr()))
agents.pi.pane_id = "w9:p9"
selection.set("opencode")
assert(chat.switch_backend("pi"))
assert(selection.get() == "opencode" and attached == 4)
assert(chat.detach(chat.active_bufnr()))

vim.fn.stdpath = original_stdpath
vim.fn.delete(isolated, "rf")
print("agents_hotswap_spec.lua: ok")
