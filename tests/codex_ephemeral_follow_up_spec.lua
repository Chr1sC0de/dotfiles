-- Use the real Tandem argument validator; intercept only process launch and UI input.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root .. "/config/nvim")
local plugin = vim.env.TANDEM_NVIM_PATH
	or (vim.fn.isdirectory(root .. "/.ci/tandem.nvim") == 1 and root .. "/.ci/tandem.nvim")
	or vim.fn.stdpath("data") .. "/lazy/tandem.nvim"
vim.opt.runtimepath:append(plugin)
local validator = require("tandem.codex")
local connection = { connected = true, root = vim.uv.fs_realpath(root), command = vim.v.progpath, state_home = root }
local launch_options
package.loaded["tandem"] = {
	codex_args = function(options)
		launch_options = options
		options.developer_instructions = ""
		return validator.args(connection, options)
	end,
}
local jobs = require("codex.ephemeral.jobs")
local panel = require("codex.ephemeral.jobs_panel")
local state = require("codex.state")
local spinner = require("codex.ephemeral.spinner")
local notice
require("codex.util").notify = function(message)
	notice = message
end
spinner.start_spinner = function()
	return function() end
end
spinner.start_diagnostic = spinner.start_spinner
local command, prompt, launches = nil, nil, 0
vim.fn.executable = function()
	return 1
end
vim.fn.jobstart = function(args)
	command, launches = args, launches + 1
	return 12345
end
vim.fn.tempname = function()
	return "/tmp/codex-follow-up-test-" .. launches
end
vim.fn.chansend = function(_, text)
	prompt = text
end
vim.fn.chanclose = function() end

local function parent(kind)
	state.ephemeral_jobs, state.ephemeral_job_order = {}, {}
	state.next_ephemeral_job_id = 1
	state.ephemeral_models.edit = "edit-model"
	local has_file = kind == "file" or kind == "selection"
	local target = {
		kind = kind,
		path = kind == "prompt" and "" or "sample.lua",
		file_path = has_file and root .. "/sample.lua" or nil,
		start_line = 2,
		end_line = 4,
		context_lines = { "Old context" },
		snapshot_path = "/deleted/snapshot",
	}
	if kind == "file" then
		vim.list_extend(target.context_lines, {
			"Unsaved buffer snapshot: /deleted/snapshot",
			"Read the snapshot file when you need the current unsaved buffer content.",
		})
	end
	local job = jobs.create("command", target, "command-model", "Explain it", {
		thread_id = "thread-123",
		reasoning_effort = "low",
		cwd = root,
	})
	job.finished_at, job.status = os.time(), "success"
	job.answer_lines = { "Use a shared helper." }
	return job
end

local function child()
	return state.ephemeral_jobs[state.ephemeral_job_order[#state.ephemeral_job_order]]
end

local function contains(text, expected)
	assert(text:find(expected, 1, true), expected .. " missing from " .. text)
end

for _, kind in ipairs({ "file", "selection", "prompt", "buffer" }) do
	local job = parent(kind)
	assert(jobs.follow_up(job, "Implement the suggestion", { action = "edit" }))
	local next_job = child()
	assert(next_job.action == "edit", "explicit edit follow-up must change action")
	assert(next_job.model == "edit-model" and next_job.reasoning_effort == nil)
	assert(next_job.parent_job_id == job.id and next_job.thread_id == nil)
	contains(table.concat(panel.result_lines(next_job), "\n"), "Parent job: #" .. job.id)
	assert(next_job.cwd == root and next_job.file_path == job.file_path)
	assert(next_job.snapshot_path == nil and job.target.snapshot_path == "/deleted/snapshot")
	assert(launch_options.read_only == false and launch_options.path == job.file_path)
	local args = table.concat(command, "\n")
	assert(not args:find("resume", 1, true), "edit jobs must start with fresh developer instructions")
	contains(prompt, "Explain it")
	contains(prompt, "Use a shared helper.")
	contains(prompt, "Old context")
	next_job.thread_id = "fresh-edit-" .. kind
	contains(args, "--sandbox\nread-only")
	contains(args, "tandem_write_file")
	assert(not args:find('model_reasoning_effort="low"', 1, true))
	assert(not args:find("Analysis-only Tandem session", 1, true))
	contains(prompt, "Implement the suggestion")
	contains(prompt, "tandem_read_file")
	contains(prompt, "tandem_write_file")
	contains(prompt, "historical")
	assert(not prompt:find("/deleted/snapshot", 1, true))
	if not job.file_path then
		contains(prompt, "Workspace: " .. root)
	else
		contains(prompt, "File: " .. job.file_path)
		if kind == "selection" then
			contains(prompt, "Lines: 2-4")
		end
	end
end

-- Continuing a promoted job inherits its edit settings, even after defaults change.
local promoted = child()
promoted.status, promoted.finished_at = "success", os.time()
state.ephemeral_models.edit = "new-default-model"
assert(jobs.follow_up(promoted, "Continue"))
assert(child().action == "edit" and child().model == promoted.model)
assert(launch_options.read_only == false and prompt == "Continue")

-- CLI-default edit model must not fall back to the command model.
local job = parent("file")
state.ephemeral_models.edit = nil
assert(jobs.follow_up(job, "Implement", { action = "edit" }))
assert(child().model == nil)
assert(not table.concat(command, "\n"):find("command-model", 1, true))

-- Ordinary follow-ups continue to inherit settings and send the instruction verbatim.
job = parent("file")
assert(jobs.follow_up(job, "Explain more"))
assert(child().action == "command" and child().model == job.model and child().reasoning_effort == "low")
assert(launch_options.read_only == true and prompt == "Explain more")

-- Both UI entrypoints prompt before editing, and f keeps its original meaning.
local function press(buf, key)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
		if mapping.lhs == key then
			mapping.callback()
			return
		end
	end
	error("Missing mapping " .. key)
end
for _, view in ipairs({ "result", "panel" }) do
	job = parent("selection")
	local buf
	if view == "result" then
		assert(panel.open_result(job))
		buf = job.result_bufnr
	else
		panel.open()
		buf = state.codex_jobs_buf
		for line, id in pairs(state.codex_jobs_line_to_id) do
			if id == job.id then
				vim.api.nvim_win_set_cursor(state.codex_jobs_win, { line, 0 })
			end
		end
	end
	local callback
	vim.ui.input = function(options, on_input)
		contains(options.prompt, "edit")
		callback = on_input
	end
	local before = launches
	press(buf, "e")
	assert(callback and launches == before, "e must prompt before launching")
	callback(nil)
	assert(launches == before, "cancelled input must not launch")
	press(buf, "e")
	callback("Apply this")
	assert(child().action == "edit" and child().file_path == job.file_path)
	child().status, child().finished_at = "success", os.time()
	vim.ui.input = function(_, on_input)
		on_input("Explain instead")
	end
	if view == "panel" then
		for line, id in pairs(state.codex_jobs_line_to_id) do
			if id == job.id then
				vim.api.nvim_win_set_cursor(state.codex_jobs_win, { line, 0 })
			end
		end
	end
	press(buf, "f")
	assert(child().action == "command")
	if view == "panel" then
		panel.close()
	end
end

-- Guards apply equally to edit follow-ups.
job = parent("file")
local before = launches
assert(jobs.follow_up(nil, "Edit", { action = "edit" }) == false)
job.finished_at = nil
assert(jobs.follow_up(job, "Edit", { action = "edit" }) == false)
job.finished_at, job.thread_id = os.time(), nil
assert(jobs.follow_up(job, "Explain") == false)
assert(jobs.follow_up(job, "Edit", { action = "edit" }))
child().status, child().finished_at = "success", os.time()
before = launches
job.thread_id = "thread-123"
assert(jobs.follow_up(job, "  ", { action = "edit" }) == false)
assert(launches == before)
assert(jobs.follow_up(job, "Edit", { action = "edit" }))
assert(jobs.follow_up(job, "Again", { action = "edit" }) == false)
contains(notice, "running follow-up")

job = parent("prompt")
job.file_path, job.target.file_path = "/outside-tandem.lua", "/outside-tandem.lua"
before = launches
assert(jobs.follow_up(job, "Edit", { action = "edit" }) == false)
assert(launches == before and child().status == "failed_to_start")
contains(notice, "outside Tandem's project")

job = parent("prompt")
connection.connected = false
before = launches
assert(jobs.follow_up(job, "Edit", { action = "edit" }) == false)
assert(launches == before and child().status == "failed_to_start")
contains(notice, "not connected")
connection.connected = true

local function complete(job, answer, thread_id)
	job.finished_at, job.status = os.time(), "success"
	job.answer_lines = { answer }
	job.thread_id = thread_id or job.thread_id
end

-- Resuming an older row uses the latest discussion; e branches from its selected result.
local first = parent("selection")
first.reference_context_lines = { "Original selected text", "local value = 42" }
assert(jobs.follow_up(first, "Second question"))
local second = child()
complete(second, "Second answer")
assert(jobs.follow_up(first, "Third question"))
local third = child()
assert(#third.history == 2 and third.history[2].instruction == "Second question")
complete(third, "Third answer")
assert(jobs.follow_up(second, "Apply second answer", { action = "edit" }))
local edit = child()
assert(#edit.history == 2 and edit.history[2].answer_lines[1] == "Second answer")
contains(prompt, "Second answer")
contains(prompt, "Original selected text")
contains(prompt, "local value = 42")
assert(not prompt:find("Third answer", 1, true))
assert(prompt:sub(-#"New instruction:\nApply second answer") == "New instruction:\nApply second answer")

-- The copied history and reference survive deletion, pruning, and later mutation.
assert(jobs.delete(first))
local constants = require("codex.constants")
local limit = constants.EPHEMERAL_RECENT_JOB_LIMIT
constants.EPHEMERAL_RECENT_JOB_LIMIT = 0
jobs.prune()
constants.EPHEMERAL_RECENT_JOB_LIMIT = limit
assert(state.ephemeral_jobs[second.id] == nil and state.ephemeral_jobs[third.id] == nil)
second.answer_lines[1] = "Changed elsewhere"
complete(edit, "Edited the selection", "fresh-edit-thread")
assert(jobs.follow_up(edit, "Another edit", { action = "edit" }))
assert(#child().history == 3 and child().history[2].answer_lines[1] == "Second answer")
contains(prompt, "Original selected text")
assert(child().thread_id == nil, "e must be fresh even for an edit parent")

-- Recover old in-memory records, including edit-labelled results from the broken transition.
first = parent("file")
first.history, first.reference_context_lines = nil, nil
local old = jobs.create("edit", first.target, "edit-model", "Old attempted edit", {
	parent_job_id = first.id,
	thread_id = first.thread_id,
})
old.history, old.reference_context_lines = nil, nil
complete(old, "Analysis-only Tandem session. Do not edit files.")
assert(jobs.follow_up(old, "Try the edit again", { action = "edit" }))
assert(#child().history == 2 and child().thread_id == nil)
contains(prompt, "Old attempted edit")
contains(prompt, "Use a shared helper.")
contains(prompt, "Old context")

-- Missing legacy ancestors are explicitly marked as incomplete.
first = parent("file")
first.history, first.reference_context_lines = nil, nil
first.parent_job_id = 999
assert(jobs.follow_up(first, "Edit retained result", { action = "edit" }))
assert(child().history_incomplete == true)
contains(prompt, "discussion is incomplete")

-- Independent fresh branches do not lock the original thread; f still checks same-thread activity.
first = parent("file")
assert(jobs.follow_up(first, "Question two"))
second = child()
complete(second, "Answer two")
assert(jobs.follow_up(second, "Still running"))
local running = child()
assert(jobs.follow_up(first, "Conflicting resume") == false)
contains(notice, "already has running job")
assert(jobs.follow_up(first, "Independent edit", { action = "edit" }))
assert(child().thread_id == nil and running.status == "running")

print("codex_ephemeral_follow_up_spec.lua: ok")
