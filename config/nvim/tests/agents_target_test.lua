vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.o.swapfile = false
vim.g.opencode_chat_test = true

local herdr = require("agents.herdr")
local attachment = require("agents.attachment")
local selection = require("agents.selection")
local chat = require("agents.chat")
local state = require("agents.state")
local util = require("agents.util")
local route = vim.fn.tempname()
vim.fn.writefile({}, route)
herdr.route_path = function() return route end
local agent = { name = "nvim-pi-td-12345-1", agent = "pi", pane_id = "pane", workspace_id = "workspace", tab_id = "other" }
assert(#herdr.filter_agents({ agent }, {}, { backend = "pi", tab_id = "other" }) == 1, "Pi prefix must match")
assert(#herdr.filter_agents({ agent }, {}, { backend = "opencode" }) == 0)
assert(#herdr.filter_agents({ agent }, {}, { tab_id = "current" }) == 0)
assert(#herdr.filter_agents({ agent }, { [agent.name] = true }) == 0)
local oc = vim.tbl_extend("force", agent, { name = herdr.agent_name(1, "opencode"), agent = "opencode" })
assert(#herdr.filter_agents({ oc }) == 1, "OpenCode prefix must still match")
vim.fn.delete(route)
assert(#herdr.filter_agents({ agent }) == 0, "route file is required")
vim.fn.writefile({}, route)

local project, revision = "project", 1
selection.project = function() return project end
selection.get = function() return "pi" end
selection.revision = function() return revision end
selection.resume = function() return nil end
herdr.available = function() return true end
vim.env.HERDR_TAB_ID = "current"
local remembered
attachment.load = function() return remembered end
local saved = 0
attachment.save = function() saved = saved + 1 end
local pending, listed, created, attached, sent
local live
chat.active_session = function() return live end
chat.focus = function() end
util.notify = function() end
vim.fn.jobwait = function() return { -1 } end
vim.api.nvim_chan_send = function(_, text) table.insert(sent, text) end
local session = { bufnr = vim.api.nvim_create_buf(false, true), job_id = 123, backend = "pi", project = "project", hook_seen = true }
chat.create = function() created = created + 1; return session end
local attach_fails = false
local external_attachment
chat._test.attach_existing_agent = function(_, _, external)
  external_attachment = external
  attached = attached + 1
  if not attach_fails then return session end
end
herdr.list_agents = function(opts) listed = listed + 1; pending = opts end
local function reset()
  pending, listed, created, attached, sent = nil, 0, 0, 0, {}
  remembered, live, attach_fails = nil, nil, false
  project, revision = "project", 1
  state.opencode_sessions = {}
end
local function remember()
  remembered = vim.tbl_extend("force", agent, { backend = "pi", project = "project" })
end
reset(); live = session
chat.paste("live")
assert(listed == 0 and created == 0 and #sent == 1)

reset(); remember()
chat.paste("one"); chat.paste("two")
assert(listed == 1, "concurrent sends share resolution")
pending.on_success({ agent })
assert(attached == 1 and created == 0 and #sent == 2, "remembered agent in another tab must be reused")
assert(saved > 0, "successful attachment is remembered")
assert(sent[1]:find("one", 1, true) and sent[2]:find("two", 1, true), "queued sends preserve order")

reset(); remember()
local external_agent = vim.tbl_extend("force", agent, { name = "manual-pi" })
remembered.name = external_agent.name
chat.paste("external"); pending.on_success({ external_agent })
assert(attached == 1 and created == 0 and external_attachment == true, "remembered external agents remain external")

reset()
local local_agent = vim.tbl_extend("force", agent, { tab_id = "current" })
chat.paste("discover"); pending.on_success({ local_agent })
assert(attached == 1 and created == 0 and #sent == 1)

reset(); remember(); remembered.pane_id = "stale"
chat.paste("fallback"); pending.on_success({ local_agent })
assert(attached == 1 and created == 0)

reset(); remember()
chat.paste("new"); pending.on_success({})
assert(created == 1 and #sent == 1)

reset(); remember(); attach_fails = true
chat.paste("failure"); pending.on_success({ agent })
assert(attached == 1 and created == 0 and #sent == 0)

reset()
chat.paste("list error"); pending.on_error(nil, "unavailable")
assert(created == 0 and #sent == 0)

reset()
chat.paste("changed"); revision = 2; pending.on_success({})
assert(created == 0 and #sent == 0, "selection change must not create or deliver")

reset()
chat.paste("project changed"); project = "another-project"; pending.on_success({})
assert(created == 0 and #sent == 0)

reset()
vim.ui.select = function(_, _, callback) callback(nil) end
chat.paste("cancel")
pending.on_success({ local_agent, vim.tbl_extend("force", local_agent, { name = "nvim-pi-td-999-1" }) })
assert(created == 0 and attached == 0 and #sent == 0)
vim.fn.delete(route)
print("agents_target_test: OK")
