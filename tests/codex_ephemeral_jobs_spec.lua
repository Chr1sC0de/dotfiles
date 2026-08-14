vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:append(".")
package.path = table.concat({
	vim.fn.getcwd() .. "/config/nvim/lua/?.lua",
	vim.fn.getcwd() .. "/config/nvim/lua/?/init.lua",
	package.path,
}, ";")

local state = require("codex.state")
local jobs = require("codex.ephemeral.jobs")
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
	state.next_ephemeral_result_id = 1
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
		vim.fn.writefile({ "answer" }, job.stdout_path)
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
	assert_contains_text(captured_prompt, "Do not modify files.", "command prompt mode")
	assert_equal(vim.fn.filereadable(job.result_path), 1, "result file")
	vim.fn.delete(job.result_path)
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
	vim.fn.delete(job.result_path)
end

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("codex_ephemeral_jobs_spec.lua: ok")
