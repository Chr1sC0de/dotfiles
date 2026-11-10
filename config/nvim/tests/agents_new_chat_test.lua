vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.o.swapfile = false
vim.g.opencode_chat_test = true
local chat = require("agents.chat")
local selection = require("agents.selection")
local herdr = require("agents.herdr")
local backend = require("agents.backend")
local tandem = require("agents.tandem")
local state = require("agents.state")
local project = vim.fn.getcwd()
selection.project = function()
	return project
end
selection.get = function()
	return "pi"
end
require("agents.util").notify = function() end
vim.fn.executable = function()
	return 1
end
vim.fn.jobwait = function()
	return { -1 }
end
vim.fn.serverstart = function()
	return "test-server"
end
tandem.config = function()
	return {}, nil, project
end
backend.environment = function()
	return {}
end
herdr.available = function()
	return true
end
herdr.prepare = function(session)
	session.launch_mode = "herdr"
	return true
end
local source = vim.api.nvim_get_current_buf()
local old = {
	id = 1,
	bufnr = vim.api.nvim_create_buf(true, false),
	backend = "pi",
	project = project,
	job_id = 100,
	hook_seen = true,
}
state.opencode_sessions = { [old.bufnr] = old }
state.opencode_session_order = { old.bufnr }
state.next_opencode_session_id = 2
selection.remember(old)
local created, launch
herdr.create_backing_agent = function(session, callbacks)
	created, launch = session, callbacks
	-- User returns to source while the asynchronous agent launch is pending.
	vim.api.nvim_set_current_buf(source)
end
herdr.attach = function()
	return 200
end
herdr.remove_route = function() end
herdr.close_pane = function() end

assert(chat.new())
assert(created and not created.native_session_id, "new chat must not resume the old conversation")
assert(chat.active_session() == created, "new foreground chat must become the send target before launch finishes")
assert(chat.paste("selection while starting"))
assert(created.pending_pastes[1] == "selection while starting", "context must queue on the new chat")
launch.on_success()
assert(chat.active_session() == created, "returning to source must not restore the old target")

-- A background launch must not steal the explicitly selected target.
local foreground = created
chat.create({ background = true })
assert(chat.active_session() == foreground, "background creation must preserve the active target")

for _, session in pairs(state.opencode_sessions) do
	for _, key in ipairs({ "task_timer", "pending_paste_timer", "paste_ready_timer" }) do
		local timer = session[key]
		if timer then
			timer:stop()
			timer:close()
			session[key] = nil
		end
	end
end
print("agents_new_chat_test: OK")
