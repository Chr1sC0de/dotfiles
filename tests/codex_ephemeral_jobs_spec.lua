vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:append(".")
package.path = table.concat({
	vim.fn.getcwd() .. "/config/nvim/lua/?.lua",
	vim.fn.getcwd() .. "/config/nvim/lua/?/init.lua",
	package.path,
}, ";")

local state = require("codex.state")
local jobs = require("codex.ephemeral.jobs")
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
		command = "gpt-5.4-mini",
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
	assert_contains_arg(captured_command, "gpt-5.4-mini", "default command model")
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

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("codex_ephemeral_jobs_spec.lua: ok")
