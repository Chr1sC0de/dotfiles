vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
dofile("tests/support/tandem.lua")
local state = require("agents.state")
local agents = require("agents.selection")
local chat = require("agents.chat")
local jobs = require("agents.ephemeral.jobs")
local panel = require("agents.ephemeral.jobs_panel")
local herdr = require("agents.herdr")
local util = require("agents.util")
local launched, notifications, next_id = {}, {}, 100
local workspace = vim.fn.getcwd()
local stdpath, isolated = vim.fn.stdpath, vim.fn.tempname()
vim.fn.stdpath = function(kind)
	return kind == "state" and isolated or stdpath(kind)
end
util.notify = function(message)
	table.insert(notifications, message)
end
vim.fn.executable = function()
	return 1
end
vim.fn.jobwait = function()
	return { -1 }
end
vim.fn.jobstart = function(args, opts)
	if opts.term then
		vim.bo.buftype = "nofile" -- mimic a terminal's non-file project resolution
	end
	next_id = next_id + 1
	table.insert(launched, { args = args, opts = opts })
	return next_id
end
vim.fn.jobstop = function() end
vim.fn.chansend = function() end
vim.fn.chanclose = function() end
vim.fn.serverstart = function()
	return "continuation-test-hooks"
end
-- Even inside Herdr, continuation must not create a backing agent/pane.
herdr.available = function()
	return true
end
herdr.prepare = function()
	error("continuation unexpectedly requested a Herdr backing pane")
end
local target = { kind = "prompt", path = "", context_lines = {} }
local function completed(backend, id, cwd)
	local job = jobs.create("query", target, nil, "question", {
		backend = backend,
		thread_id = id,
		cwd = cwd or workspace,
	})
	job.status, job.finished_at, job.answer_lines = "success", os.time(), { "answer" }
	return job
end
local function options(job)
	return { backend = job.backend, cwd = job.cwd, native_session_id = job.thread_id }
end
local function has_arg(args, arg)
	return vim.tbl_contains(args, arg)
end

-- A completed result owns the mapping, and activation uses its backend rather
-- than the selected backend. Equal IDs in different backends stay independent.
for _, id in ipairs({ "opencode", "pi" }) do
	agents.set(id == "pi" and "opencode" or "pi")
	local job = completed(id, "same-native-id")
	assert(panel.open_result(job))
	local result = job.result_bufnr
	local mapping = vim.fn.maparg("c", "n", false, true)
	assert(mapping.buffer == 1 and type(mapping.callback) == "function")
	assert(table.concat(panel.result_lines(job), "\n"):find("`c` — continue", 1, true))
	local count = #launched
	local win, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
	local windows, tabs = #vim.api.nvim_list_wins(), #vim.api.nvim_list_tabpages()
	mapping.callback()
	assert(vim.api.nvim_get_current_win() == win and vim.api.nvim_get_current_tabpage() == tab)
	assert(#vim.api.nvim_list_wins() == windows and #vim.api.nvim_list_tabpages() == tabs)
	assert(#launched == count + 1)
	local session = chat.active_session()
	assert(session and session.backend == id and session.native_session_id == job.thread_id)
	assert(session.launch_mode == "direct")
	assert(agents.get() == id and launched[#launched].opts.cwd == job.cwd)
	assert(launched[#launched].args[1] == id)
	assert(has_arg(launched[#launched].args, "--session") and has_arg(launched[#launched].args, job.thread_id))
	assert(vim.b[session.bufnr].opencode_native_session_id == job.thread_id)
	chat.toggle()
	assert(vim.api.nvim_get_current_buf() == result)
	chat.toggle()
	assert(vim.api.nvim_get_current_buf() == session.bufnr)
	vim.api.nvim_set_current_buf(result)
	assert(jobs.open_session(job))
	assert(#launched == count + 1 and chat.active_session() == session)
	assert(not jobs.follow_up(job, "another writer"))
	assert(#launched == count + 1)

	-- A terminal already visible elsewhere should be focused, not displayed
	-- for a second time in the result window.
	vim.cmd("vsplit")
	local existing_win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_set_current_buf(result)
	local reuse_windows = #vim.api.nvim_list_wins()
	assert(jobs.open_session(job))
	assert(vim.api.nvim_get_current_win() == existing_win)
	assert(vim.api.nvim_win_get_buf(win) == result)
	assert(#vim.api.nvim_list_wins() == reuse_windows and #launched == count + 1)
	vim.api.nvim_win_close(existing_win, true)

	-- Failed/cancelled results can still refer to this same conversation.
	local old = completed(id, job.thread_id)
	old.status = "cancelled"
	assert(jobs.open_session(old) and chat.active_session() == session)
	assert(#launched == count + 1)
end

assert(not jobs.open_session(nil))
local missing = completed("pi", nil)
assert(not jobs.open_session(missing))
missing.thread_id = ""
assert(not jobs.open_session(missing))
local job = completed("pi", "blocked-thread")
local active = completed("pi", job.thread_id)
active.status, active.finished_at = "running", nil
assert(not jobs.open_session(job))
active.status = "cancelling"
assert(not jobs.open_session(job))
active.status, active.finished_at = "success", os.time()

-- Same native ID elsewhere must not block or reuse this workspace's terminal.
local elsewhere = completed("pi", job.thread_id, workspace .. "/config")
elsewhere.status, elsewhere.finished_at = "running", nil
assert(jobs.open_session(job))
local original = chat.active_session()
elsewhere.status, elsewhere.finished_at = "success", os.time()
assert(jobs.open_session(elsewhere))
assert(chat.active_session() ~= original)
assert(launched[#launched].opts.cwd == elsewhere.cwd)

-- Startup failure preserves the previously selected target and result buffer.
local failing = completed("opencode", "failed-launch")
assert(panel.open_result(failing))
local result, selected = failing.result_bufnr, agents.get()
local old_start = vim.fn.jobstart
vim.fn.jobstart = function()
	return -1
end
assert(not jobs.open_session(failing))
assert(vim.api.nvim_get_current_buf() == result)
assert(agents.get() == selected)
assert(not chat.native_session_owner(options(failing)))
vim.fn.jobstart = old_start
vim.api.nvim_set_current_buf(result)

-- Herdr startup is already an owner even before terminal attachment finishes.
local pending = completed("pi", "starting-thread")
local created = 0
herdr.available = function()
	return true
end
herdr.prepare = function(session)
	session.launch_mode = "herdr"
	session.herdr_agent_name = "test-agent"
	return true
end
herdr.create_backing_agent = function()
	created = created + 1
end
-- Ordinary chat creation still defaults to Herdr (transport="auto").
local starting = chat.create({
	backend = pending.backend,
	cwd = pending.cwd,
	native_session_id = pending.thread_id,
	background = true,
})
assert(starting and starting.launch_mode == "herdr" and created == 1)
assert(chat.native_session_owner(options(pending)) == starting)
assert(starting and starting.launch_status == "starting")
assert(jobs.open_session(pending) and created == 1)
assert(not jobs.follow_up(pending, "cannot race startup"))

-- Detached owners survive removal of the Neovim terminal and reattach by exact
-- backing identity. Never launch another process into their conversation.
starting.launch_status = "attached"
starting.herdr_pane_id, starting.herdr_workspace_id = "w1:p2", "w1"
assert(chat.detach(starting.bufnr))
assert(chat.native_session_owner(options(pending)) == starting)
local count_before_detached = #launched
herdr.agent_exists = function(name, callback)
	assert(name == "test-agent")
	callback(true)
end
assert(jobs.follow_up(pending, "cannot race a detached agent"))
assert(#launched == count_before_detached)
local attach_callback, attach_count = nil, 0
chat.attach_agent = function(name, callback, expected)
	assert(name == "test-agent" and expected.pane_id == "w1:p2")
	attach_count = attach_count + 1
	attach_callback = callback
end
assert(jobs.open_session(pending))
assert(jobs.open_session(pending) and attach_count == 1)
local restored = vim.tbl_extend("force", starting, {
	bufnr = vim.api.nvim_create_buf(true, false),
	launch_status = "attached",
	job_id = 999,
})
state.opencode_sessions[restored.bufnr] = restored
table.insert(state.opencode_session_order, restored.bufnr)
vim.b[restored.bufnr].opencode_chat = true
local attach_win, attach_tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
local attach_windows, attach_tabs = #vim.api.nvim_list_wins(), #vim.api.nvim_list_tabpages()
attach_callback(restored)
assert(vim.api.nvim_get_current_win() == attach_win and vim.api.nvim_get_current_tabpage() == attach_tab)
assert(#vim.api.nvim_list_wins() == attach_windows and #vim.api.nvim_list_tabpages() == attach_tabs)
assert(created == 1, "reattachment must not create another backing agent")
assert(chat.native_session_owner(options(pending)) == restored)
assert(vim.api.nvim_get_current_buf() == restored.bufnr)

-- If the detached agent really exits, rechecking releases ownership and a
-- follow-up can safely resume. Checking twice also revalidates running jobs.
restored.launch_status = "detached"
herdr.agent_exists = function(_, callback)
	callback(false)
end
herdr.available = function()
	return false
end
assert(jobs.follow_up(pending, "now safe"))
assert(restored.exited and not chat.native_session_owner(options(pending)))
local follow = state.ephemeral_jobs[state.next_ephemeral_job_id - 1]
assert(follow.thread_id == pending.thread_id and follow.backend == pending.backend)
print("agent_job_continuation_spec.lua: ok")
