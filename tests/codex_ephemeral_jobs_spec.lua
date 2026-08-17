vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:append(".")
package.path = table.concat({
	vim.fn.getcwd() .. "/config/nvim/lua/?.lua",
	vim.fn.getcwd() .. "/config/nvim/lua/?/init.lua",
	package.path,
}, ";")

local state = require("codex.state")
local jobs = require("codex.ephemeral.jobs")
local jobs_panel = require("codex.ephemeral.jobs_panel")
local spinner = require("codex.ephemeral.spinner")
local util = require("codex.util")

local function reset_state()
	state.codex_jobs_line_highlights = {}
	state.codex_jobs_line_to_id = {}
	state.active_ephemeral_diagnostics = {}
	state.ephemeral_jobs = {}
	state.ephemeral_job_order = {}
	state.next_ephemeral_job_id = 1
	state.next_ephemeral_diagnostic_id = 1
	state.next_ephemeral_sign_id = 1
	state.ephemeral_models = {
		command = "gpt-5.6-luna",
		edit = nil,
	}
end

local function make_target(attrs)
	return vim.tbl_extend("force", {
		kind = "file",
		path = "sample.lua",
		start_line = 1,
		end_line = 1,
		modified = "no",
		context_lines = { "File: sample.lua" },
		spinner_buf = vim.api.nvim_get_current_buf(),
		spinner_line = 1,
	}, attrs or {})
end

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_contains_arg(list, expected, label)
	for _, value in ipairs(list) do
		if value == expected then
			return
		end
	end

	error(string.format("%s: expected %q in %s", label, expected, vim.inspect(list)))
end

local function assert_not_contains_arg(list, unexpected, label)
	for _, value in ipairs(list) do
		if value == unexpected then
			error(string.format("%s: did not expect %q in %s", label, unexpected, vim.inspect(list)))
		end
	end
end

local function assert_contains_text(text, expected, label)
	if not tostring(text or ""):find(expected, 1, true) then
		error(string.format("%s: expected %q in %q", label, expected, tostring(text)))
	end
end

local tests = {}

tests["command jobs use lightweight model and reasoning defaults"] = function()
	reset_state()

	local captured_command = nil
	local captured_prompt = nil
	local old_executable = vim.fn.executable
	local old_jobstart = vim.fn.jobstart
	local old_chansend = vim.fn.chansend
	local old_chanclose = vim.fn.chanclose
	local old_notify = util.notify
	local old_start_spinner = spinner.start_spinner
	local old_start_diagnostic = spinner.start_diagnostic

	vim.fn.executable = function()
		return 1
	end
	vim.fn.jobstart = function(command)
		captured_command = command
		return 123
	end
	vim.fn.chansend = function(_, prompt)
		captured_prompt = prompt
	end
	vim.fn.chanclose = function() end
	util.notify = function() end
	spinner.start_spinner = function()
		return function() end
	end
	spinner.start_diagnostic = function()
		return function() end
	end

	jobs.run("command", make_target(), "explain this")

	vim.fn.executable = old_executable
	vim.fn.jobstart = old_jobstart
	vim.fn.chansend = old_chansend
	vim.fn.chanclose = old_chanclose
	util.notify = old_notify
	spinner.start_spinner = old_start_spinner
	spinner.start_diagnostic = old_start_diagnostic

	assert_contains_arg(captured_command, "--model", "model flag")
	assert_contains_arg(captured_command, "gpt-5.6-luna", "default command model")
	assert_contains_arg(captured_command, 'model_reasoning_effort="low"', "reasoning override")
	assert_contains_arg(captured_command, "--sandbox", "sandbox flag")
	assert_contains_arg(captured_command, "read-only", "read-only sandbox")
	assert_contains_arg(captured_command, "--json", "JSON events")
	assert_contains_arg(captured_command, "--output-last-message", "final message output")
	assert_not_contains_arg(captured_command, "--ephemeral", "persisted session")
	assert_contains_text(captured_prompt, "Do not modify files.", "command prompt mode")
end

tests["edit jobs refuse modified buffers"] = function()
	reset_state()

	local jobstarted = false
	local notifications = {}
	local old_executable = vim.fn.executable
	local old_jobstart = vim.fn.jobstart
	local old_notify = util.notify

	vim.fn.executable = function()
		return 1
	end
	vim.fn.jobstart = function()
		jobstarted = true
		return 123
	end
	util.notify = function(message)
		table.insert(notifications, message)
	end

	jobs.run("edit", make_target({ modified = "yes" }), "fix it")

	vim.fn.executable = old_executable
	vim.fn.jobstart = old_jobstart
	util.notify = old_notify

	assert_equal(jobstarted, false, "job started")
	assert_equal(notifications[1], "Save the buffer before running ephemeral Codex edits", "notification")
end

tests["direct jobs start independently for parallel execution"] = function()
	reset_state()

	local started = {}
	local old_executable = vim.fn.executable
	local old_jobstart = vim.fn.jobstart
	local old_chansend = vim.fn.chansend
	local old_chanclose = vim.fn.chanclose
	local old_notify = util.notify
	local old_start_spinner = spinner.start_spinner
	local old_start_diagnostic = spinner.start_diagnostic

	vim.fn.executable = function()
		return 1
	end
	vim.fn.jobstart = function(command)
		table.insert(started, command)
		return 120 + #started
	end
	vim.fn.chansend = function() end
	vim.fn.chanclose = function() end
	util.notify = function() end
	spinner.start_spinner = function()
		return function() end
	end
	spinner.start_diagnostic = function()
		return function() end
	end

	jobs.run("command", make_target(), "explain one")
	jobs.run("command", make_target(), "explain two")

	vim.fn.executable = old_executable
	vim.fn.jobstart = old_jobstart
	vim.fn.chansend = old_chansend
	vim.fn.chanclose = old_chanclose
	util.notify = old_notify
	spinner.start_spinner = old_start_spinner
	spinner.start_diagnostic = old_start_diagnostic

	assert_equal(#started, 2, "parallel processes")
	assert_equal(state.ephemeral_jobs[1].transport, "direct", "first transport")
	assert_equal(state.ephemeral_jobs[2].transport, "direct", "second transport")
	assert_equal(state.ephemeral_jobs[1].job_id, 121, "first process")
	assert_equal(state.ephemeral_jobs[2].job_id, 122, "second process")
end

tests["follow-ups resume the captured thread and inherit job settings"] = function()
	reset_state()

	local captured_command = nil
	local captured_prompt = nil
	local old_executable = vim.fn.executable
	local old_jobstart = vim.fn.jobstart
	local old_chansend = vim.fn.chansend
	local old_chanclose = vim.fn.chanclose
	local old_notify = util.notify
	local old_start_spinner = spinner.start_spinner
	local old_start_diagnostic = spinner.start_diagnostic

	vim.fn.executable = function()
		return 1
	end
	vim.fn.jobstart = function(command)
		captured_command = command
		return 456
	end
	vim.fn.chansend = function(_, prompt)
		captured_prompt = prompt
	end
	vim.fn.chanclose = function() end
	util.notify = function() end
	spinner.start_spinner = function()
		return function() end
	end
	spinner.start_diagnostic = function()
		return function() end
	end

	local parent = jobs.create("command", make_target(), "gpt-test", "first question", {
		cwd = "/tmp/project",
		reasoning_effort = "low",
		sandbox = "read-only",
		thread_id = "thread-123",
	})
	parent.finished_at = os.time()
	parent.status = "success"
	assert_equal(jobs.follow_up(parent, "clarify that"), true, "follow-up started")
	local child = state.ephemeral_jobs[2]

	vim.fn.executable = old_executable
	vim.fn.jobstart = old_jobstart
	vim.fn.chansend = old_chansend
	vim.fn.chanclose = old_chanclose
	util.notify = old_notify
	spinner.start_spinner = old_start_spinner
	spinner.start_diagnostic = old_start_diagnostic

	assert_contains_arg(captured_command, "resume", "resume subcommand")
	assert_contains_arg(captured_command, "thread-123", "resume thread")
	assert_contains_arg(captured_command, "/tmp/project", "inherited cwd")
	assert_equal(captured_prompt, "clarify that", "follow-up prompt")
	assert_equal(child.parent_job_id, parent.id, "parent job")
	assert_equal(child.thread_id, parent.thread_id, "child thread")
end

tests["result view shows commands, response, details, and failure stderr"] = function()
	reset_state()
	local job =
		jobs.create("command", make_target({ start_line = 2, end_line = 4 }), "gpt-test", "Explain this\ncarefully")
	job.answer_lines = { "The answer.", "", "- Detail" }
	job.exit_code = 0
	job.finished_at = os.time()
	job.status = "success"
	job.stderr_lines = { "progress noise" }
	job.thread_id = "thread-123"

	local rendered = table.concat(jobs_panel.result_lines(job), "\n")
	assert_equal(rendered:sub(1, #"## Commands"), "## Commands", "commands first")
	assert_contains_text(rendered, "## Response\n\nThe answer.", "response")
	assert_contains_text(rendered, "## Job details", "job details")
	assert_contains_text(rendered, "> Explain this\n> carefully", "quoted instruction")
	assert_equal(rendered:find("progress noise", 1, true), nil, "successful stderr hidden")

	job.status = "failed"
	local failed = table.concat(jobs_panel.result_lines(job), "\n")
	assert_contains_text(failed, "## Error output", "failure heading")
	assert_contains_text(failed, "progress noise", "failure stderr")
end

tests["completed results open in reusable dedicated tabs"] = function()
	reset_state()
	local notifications = {}
	local old_notify = util.notify
	util.notify = function(message)
		table.insert(notifications, message)
	end
	local return_bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(return_bufnr)
	local return_tabpage = vim.api.nvim_get_current_tabpage()
	local initial_tab_count = #vim.api.nvim_list_tabpages()
	assert_equal(initial_tab_count, 1, "isolated test tab count")

	local job = jobs.create("command", make_target(), "gpt-test", "Explain this")
	job.answer_lines = { "The answer." }
	job.exit_code = 0
	job.finished_at = os.time()
	job.status = "success"
	job.thread_id = "thread-123"
	assert_equal(jobs_panel.open_result(job), true, "result opened")

	assert_equal(#vim.api.nvim_list_tabpages(), initial_tab_count + 1, "new result tab")
	assert_equal(job.result_return_tabpage, return_tabpage, "return tab")
	assert_equal(vim.api.nvim_get_current_tabpage(), job.result_tabpage, "current result tab")
	assert_equal(vim.api.nvim_get_current_buf(), job.result_bufnr, "current result buffer")
	local return_win = vim.api.nvim_tabpage_get_win(return_tabpage)
	assert_equal(vim.api.nvim_win_get_buf(return_win), return_bufnr, "origin buffer preserved")
	assert_equal(vim.api.nvim_buf_get_name(job.result_bufnr), "codex://job/1", "result buffer name")
	assert_equal(vim.bo[job.result_bufnr].buftype, "nofile", "result buffer type")
	assert_equal(vim.bo[job.result_bufnr].filetype, "markdown", "result filetype")
	assert_equal(vim.bo[job.result_bufnr].modifiable, false, "result is read-only")

	local mappings = vim.api.nvim_buf_get_keymap(job.result_bufnr, "n")
	local mapped = {}
	for _, mapping in ipairs(mappings) do
		mapped[mapping.lhs] = true
	end
	assert_equal(mapped.f, true, "follow-up mapping")
	assert_equal(mapped.s, true, "source mapping")
	assert_equal(mapped.g, nil, "g prefix remains unmapped")
	assert_equal(mapped.q, true, "close mapping")
	assert_equal(mapped["<Esc>"], true, "escape mapping")

	assert_equal(jobs_panel.open_result(job), true, "visible result reopened")
	assert_equal(#vim.api.nvim_list_tabpages(), initial_tab_count + 1, "visible result tab reused")
	vim.api.nvim_set_current_tabpage(return_tabpage)
	assert_equal(jobs_panel.open_result(job), true, "result reopened from origin")
	assert_equal(#vim.api.nvim_list_tabpages(), initial_tab_count + 1, "origin reopen reused result tab")

	local close_callback = nil
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(job.result_bufnr, "n")) do
		if mapping.lhs == "q" then
			close_callback = mapping.callback
			break
		end
	end
	assert_equal(type(close_callback), "function", "close callback")
	close_callback()
	assert_equal(#vim.api.nvim_list_tabpages(), initial_tab_count, "result tab closed")
	assert_equal(vim.api.nvim_get_current_tabpage(), return_tabpage, "origin tab restored")
	assert_equal(vim.api.nvim_get_current_buf(), return_bufnr, "origin buffer restored")
	assert_equal(vim.api.nvim_buf_is_valid(job.result_bufnr), true, "closed result remains reusable")

	local result_bufnr = job.result_bufnr
	assert_equal(jobs.delete(job), true, "job deleted")
	assert_equal(vim.api.nvim_buf_is_valid(result_bufnr), false, "result buffer wiped")

	local edit_job = jobs.create("edit", make_target(), nil, "Fix this")
	edit_job.answer_lines = { "Updated." }
	edit_job.exit_code = 0
	edit_job.finished_at = os.time()
	edit_job.status = "success"
	assert_equal(jobs_panel.open_result(edit_job), true, "edit result opened")
	assert_equal(#vim.api.nvim_list_tabpages(), initial_tab_count + 1, "edit result tab")
	assert_equal(vim.api.nvim_get_current_buf(), edit_job.result_bufnr, "current edit result")
	vim.api.nvim_set_current_tabpage(return_tabpage)
	vim.cmd("tabclose")
	assert_equal(#vim.api.nvim_list_tabpages(), 1, "origin tab closed")
	assert_equal(vim.api.nvim_get_current_buf(), edit_job.result_bufnr, "edit result remains")
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(edit_job.result_bufnr, "n")) do
		if mapping.lhs == "q" then
			mapping.callback()
			break
		end
	end
	assert_equal(#vim.api.nvim_list_tabpages(), 1, "last tab retained")
	assert_equal(vim.api.nvim_get_current_buf(), return_bufnr, "closed-origin buffer fallback")
	assert_equal(jobs.delete(edit_job), true, "edit job deleted")
	util.notify = old_notify
end

tests["a thread rejects concurrent follow-ups"] = function()
	reset_state()
	local notifications = {}
	local old_notify = util.notify
	local old_executable = vim.fn.executable
	util.notify = function(message)
		table.insert(notifications, message)
	end
	vim.fn.executable = function()
		return 1
	end

	local parent = jobs.create("command", make_target(), "gpt-test", "first", { thread_id = "thread-123" })
	parent.finished_at = os.time()
	parent.status = "success"
	local active = jobs.create("command", make_target(), "gpt-test", "second", { thread_id = "thread-123" })
	active.status = "running"

	assert_equal(jobs.follow_up(parent, "third"), false, "concurrent follow-up")
	assert_contains_text(notifications[#notifications], "already has running job #" .. active.id, "concurrency warning")

	vim.fn.executable = old_executable
	util.notify = old_notify
end

tests["direct cancellation stops the background process"] = function()
	reset_state()

	local stopped_job = nil
	local old_jobstop = vim.fn.jobstop
	local old_notify = util.notify
	util.notify = function() end
	vim.fn.jobstop = function(job_id)
		stopped_job = job_id
	end

	local target = make_target()
	local job = jobs.create("edit", target, nil, "fix it")
	job.job_id = 73
	job.status = "running"
	job.stop_activity = function() end
	job.target = target
	job.transport = "direct"
	jobs.cancel(job)

	vim.fn.jobstop = old_jobstop
	util.notify = old_notify

	assert_equal(stopped_job, 73, "stopped process")
	assert_equal(job.status, "cancelling", "job status")
end

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("codex_ephemeral_jobs_spec.lua: ok")
