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
local herdr = require("codex.herdr")
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
	local old_ephemeral_available = herdr.ephemeral_available
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
	herdr.ephemeral_available = function()
		return false
	end
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
	herdr.ephemeral_available = old_ephemeral_available
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
	local old_ephemeral_available = herdr.ephemeral_available

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
	herdr.ephemeral_available = function()
		return false
	end

	jobs.run("edit", make_target({ modified = "yes" }), "fix it")

	vim.fn.executable = old_executable
	vim.fn.jobstart = old_jobstart
	util.notify = old_notify
	herdr.ephemeral_available = old_ephemeral_available

	assert_equal(jobstarted, false, "job started")
	assert_equal(notifications[1], "Save the buffer before running ephemeral Codex edits", "notification")
end

tests["Herdr jobs preserve the Neovim result lifecycle"] = function()
	reset_state()

	local captured_prompt = nil
	local direct_started = false
	local old_executable = vim.fn.executable
	local old_jobstart = vim.fn.jobstart
	local old_notify = util.notify
	local old_ephemeral_available = herdr.ephemeral_available
	local old_launch_ephemeral = herdr.launch_ephemeral
	local old_start_spinner = spinner.start_spinner
	local old_start_diagnostic = spinner.start_diagnostic

	vim.fn.executable = function()
		return 1
	end
	vim.fn.jobstart = function()
		direct_started = true
		return 123
	end
	util.notify = function() end
	herdr.ephemeral_available = function()
		return true
	end
	herdr.launch_ephemeral = function(job, opts)
		captured_prompt = table.concat(vim.fn.readfile(job.prompt_path), "\n")
		vim.fn.writefile({
			vim.json.encode({ type = "thread.started", thread_id = "thread-123" }),
			vim.json.encode({
				type = "item.completed",
				item = { type = "agent_message", text = "fallback answer" },
			}),
		}, job.stdout_path)
		vim.fn.writefile({ "answer", "", "More detail." }, job.result_message_path)
		vim.fn.writefile({}, job.stderr_path)
		vim.fn.writefile({ "0" }, job.status_path)
		opts.on_success()
	end
	spinner.start_spinner = function()
		return function() end
	end
	spinner.start_diagnostic = function()
		return function() end
	end

	jobs.run("command", make_target(), "explain this")
	local job = state.ephemeral_jobs[1]

	vim.fn.executable = old_executable
	vim.fn.jobstart = old_jobstart
	util.notify = old_notify
	herdr.ephemeral_available = old_ephemeral_available
	herdr.launch_ephemeral = old_launch_ephemeral
	spinner.start_spinner = old_start_spinner
	spinner.start_diagnostic = old_start_diagnostic

	assert_equal(direct_started, false, "direct transport")
	assert_equal(job.transport, "herdr", "job transport")
	assert_equal(job.status, "success", "job status")
	assert_equal(job.exit_code, 0, "exit code")
	assert_equal(job.thread_id, "thread-123", "thread id")
	assert_equal(table.concat(job.answer_lines, "\n"), "answer\n\nMore detail.", "final answer")
	assert_contains_text(captured_prompt, "Do not modify files.", "command prompt mode")
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
	local old_ephemeral_available = herdr.ephemeral_available
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
	herdr.ephemeral_available = function()
		return false
	end
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
	herdr.ephemeral_available = old_ephemeral_available
	spinner.start_spinner = old_start_spinner
	spinner.start_diagnostic = old_start_diagnostic

	assert_contains_arg(captured_command, "resume", "resume subcommand")
	assert_contains_arg(captured_command, "thread-123", "resume thread")
	assert_contains_arg(captured_command, "/tmp/project", "inherited cwd")
	assert_equal(captured_prompt, "clarify that", "follow-up prompt")
	assert_equal(child.parent_job_id, parent.id, "parent job")
	assert_equal(child.thread_id, parent.thread_id, "child thread")
end

tests["result view is answer-first and only shows failure stderr"] = function()
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
	assert_equal(rendered:sub(1, #"The answer."), "The answer.", "answer first")
	assert_contains_text(rendered, "## Job details", "job details")
	assert_contains_text(rendered, "> Explain this\n> carefully", "quoted instruction")
	assert_equal(rendered:find("progress noise", 1, true), nil, "successful stderr hidden")

	job.status = "failed"
	local failed = table.concat(jobs_panel.result_lines(job), "\n")
	assert_contains_text(failed, "## Error output", "failure heading")
	assert_contains_text(failed, "progress noise", "failure stderr")
end

tests["completed results open as disposable named scratch buffers"] = function()
	reset_state()
	local notifications = {}
	local old_notify = util.notify
	util.notify = function(message)
		table.insert(notifications, message)
	end

	local job = jobs.create("command", make_target(), "gpt-test", "Explain this")
	job.answer_lines = { "The answer." }
	job.exit_code = 0
	job.finished_at = os.time()
	job.status = "success"
	job.thread_id = "thread-123"
	assert_equal(jobs_panel.open_result(job), true, "result opened")

	assert_equal(vim.api.nvim_get_current_buf(), job.result_bufnr, "current result buffer")
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

	local result_bufnr = job.result_bufnr
	assert_equal(jobs.delete(job), true, "job deleted")
	assert_equal(vim.api.nvim_buf_is_valid(result_bufnr), false, "result buffer wiped")
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

tests["Herdr cancellation closes the backing tab and finalizes the job"] = function()
	reset_state()

	local closed_tab = nil
	local old_close_tab = herdr.close_tab
	local old_notify = util.notify
	util.notify = function() end
	herdr.close_tab = function(job, opts)
		closed_tab = job.herdr_tab_id
		opts.on_success()
	end

	local target = make_target()
	local job = jobs.create("edit", target, nil, "fix it")
	job.herdr_tab_id = "w7:t3"
	job.status = "running"
	job.stop_activity = function() end
	job.target = target
	job.transport = "herdr"
	jobs.cancel(job)

	herdr.close_tab = old_close_tab
	util.notify = old_notify

	assert_equal(closed_tab, "w7:t3", "closed tab")
	assert_equal(job.status, "cancelled", "job status")
	assert_equal(job.exit_code, 130, "exit code")
end

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("codex_ephemeral_jobs_spec.lua: ok")
