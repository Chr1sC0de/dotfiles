vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local stdpath, isolated = vim.fn.stdpath, vim.fn.tempname()
vim.fn.stdpath = function(kind)
	return kind == "state" and isolated or stdpath(kind)
end
dofile("tests/support/tandem.lua")
local agents = require("agents.selection")
local backend = require("agents.backend")
local state = require("agents.state")
local chat = require("agents.chat")
local herdr = require("agents.herdr")
local jobs = require("agents.ephemeral.jobs")
local model = require("agents.ephemeral.model")
local attachment = require("agents.attachment")
vim.notify = function() end
local project = agents.project()
agents.set("opencode")

local launched, sent, next_id = {}, {}, 40
vim.fn.executable = function()
	return 1
end
vim.fn.jobwait = function()
	return { -1 }
end
vim.fn.jobstart = function(args, opts)
	next_id = next_id + 1
	launched[next_id] = { args = args, opts = opts }
	return next_id
end
vim.fn.chansend = function(id, text)
	sent[#sent + 1] = { id = id, text = text }
end
vim.fn.chanclose = function() end
vim.api.nvim_chan_send = vim.fn.chansend
vim.fn.serverstart = function()
	return "test-hook-server"
end
herdr.available = function()
	return false
end

assert(chat.new())
local oc = chat.active_session()
oc.paste_ready = true
assert(oc.backend == "opencode" and launched[oc.job_id].args[1] == "opencode")
assert(chat.switch_backend("pi"))
local pi = chat.active_session()
pi.paste_ready = true
assert(pi ~= oc and pi.backend == "pi" and launched[pi.job_id].args[1] == "pi")
assert(launched[pi.job_id].opts.env.TANDEM_EDITOR)
assert(chat.paste("Pi prompt"))
assert(sent[#sent].id == pi.job_id)
assert(chat.switch_backend("opencode"))
assert(chat.active_session() == oc and not pi.exited)
assert(chat.paste("Agent prompt"))
assert(sent[#sent].id == oc.job_id)
assert(chat.paste("explicit Pi", { bufnr = pi.bufnr }))
assert(sent[#sent].id == pi.job_id and agents.get() == "opencode")
assert(chat.focus(pi.bufnr) and agents.get() == "pi")
vim.fn.executable = function(id)
	return id == "opencode" and 0 or 1
end
assert(not chat.switch_backend("opencode") and chat.active_session() == pi)
assert(not chat.switch_backend("invalid") and agents.get() == "pi")
vim.fn.executable = function()
	return 1
end

-- Preferences and their persisted files are independent, including CLI default.
model.set("query", "pi/model", "pi")
model.set("query", "oc/model", "opencode")
assert(model.get("query", "pi") == "pi/model" and model.get("query", "opencode") == "oc/model")
model.set("query", nil, "pi")
assert(model.get("query", "pi") == nil and model.get("query", "opencode") == "oc/model")
assert(require("agents.ephemeral.preferences").path("pi") ~= require("agents.ephemeral.preferences").path("opencode"))

-- Native IDs can coincide. Running work and promotion remain backend-owned.
local target = { kind = "file", file_path = vim.fn.getcwd() .. "/test.lua", context_lines = {}, source_buf = 1 }
local original = jobs.create("query", target, nil, "first", { backend = "pi", thread_id = "same-id" })
original.status, original.finished_at, original.answer_lines = "success", os.time(), { "Pi answer" }
local other = jobs.create("query", target, nil, "other", { backend = "opencode", thread_id = "same-id" })
other.status = "running"
agents.set("opencode")
assert(jobs.follow_up(original, "continue"))
local follow = state.ephemeral_jobs[state.next_ephemeral_job_id - 1]
assert(follow.backend == "pi" and follow.thread_id == "same-id")
assert(launched[follow.job_id].args[1] == "pi")
assert(not jobs.follow_up(original, "duplicate"))
follow.finished_at, follow.status = os.time(), "success"
assert(jobs.follow_up(original, "promote", { action = "edit" }))
assert(state.ephemeral_jobs[state.next_ephemeral_job_id - 1].backend == "pi")

-- Picker callbacks and queued launches cannot change destination after a switch.
local pending_input
vim.ui.input = function(_, callback)
	pending_input = callback
end
agents.set("pi")
jobs.prompt_and_run("query", target)
agents.set("opencode")
pending_input("delayed Pi question")
assert(state.ephemeral_jobs[state.next_ephemeral_job_id - 1].backend == "pi")

oc.exited, pi.exited = true, true
local list_callback
herdr.available = function()
	return true
end
herdr.list_agents = function(opts)
	list_callback = opts.on_success
end
agents.set("pi")
assert(chat.paste("queued Pi prompt"))
agents.set("opencode")
local foreground = vim.api.nvim_get_current_buf()
-- Complete a delayed discovery after the switch. A new background Pi session
-- retains the queued context without activating itself or using Agent.
herdr.available = function()
	return false
end
list_callback({})
assert(agents.get() == "opencode" and vim.api.nvim_get_current_buf() == foreground)
local background = chat.list()[1]
assert(background.backend == "pi" and background.pending_pastes[1] == "queued Pi prompt")

-- Attachment persistence and validation never cross backends.
local identity = { herdr_agent_name = "pi-agent", herdr_pane_id = "w1:p1", herdr_workspace_id = "w1", backend = "pi" }
attachment.save(project, identity)
assert(attachment.load(project, "pi").backend == "pi")
assert(not attachment.load(project, "opencode"))
assert(
	attachment.matches(
		attachment.load(project, "pi"),
		{ name = "pi-agent", pane_id = "w1:p1", workspace_id = "w1", agent = "pi" }
	)
)
assert(
	not attachment.matches(
		attachment.load(project, "pi"),
		{ name = "pi-agent", pane_id = "w1:p1", workspace_id = "w1", agent = "opencode" }
	)
)

local args = herdr.agent_start_args({
	backend = "pi",
	cwd = "/project",
	tandem_env = {},
	herdr_agent_name = "test",
	herdr_pane_id = "w1:p1",
})
assert(args[5] == "pi" and not vim.tbl_contains(args, "--standalone"))
assert(vim.tbl_contains(args, "--extension"))
assert(vim.fn.filereadable(backend.get("pi").plugin_path()) == 1)

-- Native session restoration is namespaced and survives reloading selection.
chat.focus(background.bufnr)
herdr.available = function()
	return true
end
local managed_launch
herdr.create_backing_agent = function(_, opts)
	managed_launch = opts
end
assert(chat.switch_backend("opencode") and agents.get() == "opencode")
managed_launch.on_error(nil, "managed launch failed")
assert(agents.get() == "pi" and chat.active_session() == background)
herdr.available = function()
	return false
end

agents.remember_native({ project = project, backend = "pi", native_session_id = "pi-native" })
agents.remember_native({ project = project, backend = "opencode", native_session_id = "oc-native" })
assert(agents.resume(project, "pi") == "pi-native" and agents.resume(project, "opencode") == "oc-native")
agents.set("pi", project)
package.loaded["agents.selection"] = nil
assert(require("agents.selection").get(project) == "pi")
vim.fn.stdpath = stdpath
vim.fn.delete(isolated, "rf")
print("agent_backends_spec.lua: ok")
