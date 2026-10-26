vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary .. "/project/.git", "p")
vim.fn.mkdir(temporary .. "/other/.git", "p")
local original_stdpath, original_cwd = vim.fn.stdpath, vim.fn.getcwd()
vim.fn.stdpath = function(kind)
	return kind == "state" and temporary .. "/state" or original_stdpath(kind)
end
vim.cmd.cd(temporary .. "/project")
vim.g.opencode_chat_test = true
local chat = require("opencode.chat")
local herdr = require("opencode.herdr")
local state = require("opencode.state")
vim.notify = function() end
local function equal(a, b)
	assert(vim.deep_equal(a, b), vim.inspect(a) .. " != " .. vim.inspect(b))
end
local agent =
	{ name = "external", agent = "opencode", pane_id = "w2:p1", workspace_id = "w2", tab_id = "w2:t1", cwd = "/tmp" }
local attached, stopped, pasted = 0, {}, {}
local exit_callback
herdr.get_agent = function(_, callback)
	callback(agent)
end
herdr.attach = function(_, callback)
	attached = attached + 1
	exit_callback = callback
	return 1000 + attached
end
herdr.prepare = function()
	error("external attachment must not write routing")
end
herdr.report_host = function()
	error("external attachment must not claim host ownership")
end
herdr.close_pane = function()
	error("external attachment must not close panes")
end
herdr.remove_route = function()
	error("external attachment must not remove routes")
end
vim.fn.jobwait = function()
	return { -1 }
end
vim.fn.jobstop = function(job)
	stopped[#stopped + 1] = job
end
vim.api.nvim_chan_send = function(job, text)
	pasted[#pasted + 1] = { job, text }
end

chat.attach_agent("external")
local session = chat.active_session()
assert(session and session.external_attachment)
equal(session.tandem_configured, false)
equal(chat.ipc_status_label(session), "UNAVAIL")
equal(vim.b[session.bufnr].opencode_external_attachment, true)
state.opencode_sessions[session.bufnr] = nil
session = chat.session(session.bufnr)
assert(session.external_attachment, "buffer recovery must preserve external ownership")
chat.attach_agent("external")
equal(attached, 1)
session.paste_ready = true
assert(chat.paste("hello agent"))
assert(#pasted > 0 and pasted[1][1] == session.job_id)
assert(pasted[1][2]:find("hello agent", 1, true))

local old_buffer = session.bufnr
assert(chat.detach(old_buffer))
equal(stopped, { 1001 })
equal(state.opencode_sessions[old_buffer], nil)
equal(vim.api.nvim_buf_is_valid(old_buffer), false)
-- The registry is empty after detach, as after restarting Neovim. Toggle must
-- restore the disk-backed identity rather than discover/create another agent.
chat.toggle()
equal(attached, 2)
session = chat.active_session()
assert(chat.delete_buffer(session.bufnr)) -- Existing session-panel deletion only detaches externals.
equal(stopped, { 1001, 1002 })

chat.attach_agent("external")
session = chat.active_session()
old_buffer = session.bufnr
herdr.agent_exists = function(_, callback)
	callback(false)
end
exit_callback(session.job_id, 0)
assert(vim.wait(1000, function()
	return state.opencode_sessions[old_buffer] == nil
end))
equal(vim.api.nvim_buf_is_valid(old_buffer), false)

-- Overlapping asynchronous requests attach only once.
local resolve
herdr.get_agent = function(_, callback)
	resolve = callback
end
chat.attach_agent("external")
chat.attach_agent("external")
resolve(agent)
equal(attached, 4)
chat.detach(chat.active_bufnr())
herdr.get_agent = function(_, callback)
	callback(agent)
end
herdr.attach = function()
	return nil
end
local failed_session
chat.attach_agent("external", function(value)
	failed_session = value
end)
assert(failed_session.external_attachment)
equal(failed_session.launch_status, "detached")
assert(not chat.is_running(failed_session.bufnr))
chat.detach(failed_session.bufnr)

local attachment = require("opencode.attachment")
local project = attachment.project()
local saved = attachment.load(project)
assert(saved and saved.name == "external")
package.loaded["opencode.attachment"] = nil
equal(require("opencode.attachment").load(project), saved)
vim.cmd.cd(temporary .. "/other")
equal(attachment.load(attachment.project()), nil)
vim.cmd.cd(temporary .. "/project")

-- A reused name in another pane must not silently become the remembered chat.
local prompted, dashboard = 0, 0
local original_select = vim.ui.select
vim.ui.select = function(choices, _, callback)
	prompted = prompted + 1
	callback(choices[1])
end
chat.attach_existing = function() dashboard = dashboard + 1 end
agent.pane_id = "w9:p9"
chat.toggle()
equal(prompted, 1)
equal(dashboard, 1)
equal(attachment.load(project), saved)
equal(attached, 4)

-- A delayed lookup must not attach into a different project.
herdr.get_agent = function(_, callback) resolve = callback end
chat.attach_agent("external")
vim.cmd.cd(temporary .. "/other")
resolve(agent)
equal(attached, 4)
vim.ui.select = original_select
vim.cmd.cd(original_cwd)
vim.fn.stdpath = original_stdpath
vim.fn.delete(temporary, "rf")
print("opencode_external_attachment_spec.lua: ok")
