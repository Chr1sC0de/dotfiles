local constants = require("codex.constants")
local state = require("codex.state")
local model = require("codex.ephemeral.model")
local spinner = require("codex.ephemeral.spinner")
local util = require("codex.util")

local M = {}

function M.is_active(job)
	return job and (job.status == "starting" or job.status == "running" or job.status == "cancelling")
end

function M.refresh_panel()
	local ok, panel = pcall(require, "codex.ephemeral.jobs_panel")
	if ok then
		panel.refresh_open()
	end
end

function M.prune()
	local completed = {}
	for _, id in ipairs(state.ephemeral_job_order) do
		local job = state.ephemeral_jobs[id]
		if job and not M.is_active(job) then
			table.insert(completed, id)
		end
	end

	while #completed > constants.EPHEMERAL_RECENT_JOB_LIMIT do
		local id = table.remove(completed, 1)
		local job = state.ephemeral_jobs[id]
		if job and util.is_valid_buffer(job.result_bufnr) then
			pcall(vim.api.nvim_buf_delete, job.result_bufnr, { force = true })
		end
		state.ephemeral_jobs[id] = nil
	end

	local next_order = {}
	for _, id in ipairs(state.ephemeral_job_order) do
		if state.ephemeral_jobs[id] then
			table.insert(next_order, id)
		end
	end
	state.ephemeral_job_order = next_order
end

function M.create(action, target, selected_model, instruction, attrs)
	attrs = attrs or {}
	local id = state.next_ephemeral_job_id
	state.next_ephemeral_job_id = state.next_ephemeral_job_id + 1

	local job = {
		answer_lines = {},
		id = id,
		action = action,
		cancel_requested = false,
		completion_timer = nil,
		cwd = attrs.cwd or vim.fn.getcwd(),
		exit_code = nil,
		finished_at = nil,
		herdr_pane_id = nil,
		herdr_tab_id = nil,
		herdr_workspace_id = nil,
		instruction = instruction,
		job_id = nil,
		kind = target.kind,
		model = selected_model,
		parent_job_id = attrs.parent_job_id,
		path = target.path,
		prompt_path = nil,
		reasoning_effort = attrs.reasoning_effort,
		result_bufnr = nil,
		result_message_path = nil,
		result_return_bufnr = nil,
		result_return_tabpage = nil,
		result_tabpage = nil,
		sandbox = attrs.sandbox or (action == "edit" and "workspace-write" or "read-only"),
		snapshot_path = target.snapshot_path,
		start_line = target.start_line,
		started_at = os.time(),
		status = "starting",
		status_path = nil,
		stderr_path = nil,
		stderr_lines = {},
		stdout_path = nil,
		stop_activity = nil,
		target = target,
		end_line = target.end_line,
		transport = nil,
		thread_id = attrs.thread_id,
	}
	state.ephemeral_jobs[id] = job
	table.insert(state.ephemeral_job_order, id)
	M.refresh_panel()

	return job
end

function M.update(job, attrs)
	if not job then
		return
	end

	for key, value in pairs(attrs) do
		job[key] = value
	end

	if job.finished_at then
		M.prune()
	end
	M.refresh_panel()
end

function M.delete(job)
	if not job then
		util.notify("Codex job not found", vim.log.levels.WARN)
		return false
	end

	if M.is_active(job) then
		util.notify("Codex job #" .. job.id .. " is still running; cancel it with x first", vim.log.levels.WARN)
		return false
	end
	if util.is_valid_buffer(job.result_bufnr) then
		pcall(vim.api.nvim_buf_delete, job.result_bufnr, { force = true })
	end

	state.ephemeral_jobs[job.id] = nil
	local next_order = {}
	for _, id in ipairs(state.ephemeral_job_order) do
		if id ~= job.id then
			table.insert(next_order, id)
		end
	end
	state.ephemeral_job_order = next_order
	M.refresh_panel()
	util.notify("Deleted Codex job #" .. job.id .. " from the session list")
	return true
end

function M.delete_by_id(id)
	return M.delete(state.ephemeral_jobs[tonumber(id)])
end

local function build_ephemeral_prompt(action, instruction, target)
	local mode_description
	if action == "edit" then
		mode_description =
			"Apply the user's requested edits if appropriate. Keep changes scoped to the supplied context."
	else
		mode_description = "Answer the user's instruction using the supplied context. Do not modify files."
	end

	local lines = {
		"You are running as an ephemeral Codex job from Neovim.",
		mode_description,
		"",
		"Instruction:",
		instruction,
	}

	if target.kind ~= "prompt" then
		vim.list_extend(lines, {
			"",
			"Target: " .. target.kind,
		})
		vim.list_extend(lines, target.context_lines)
	end

	return table.concat(lines, "\n")
end

function M.command_args(job)
	local command = {
		"codex",
		"exec",
		"--json",
		"--sandbox",
		job.sandbox,
		"--cd",
		job.cwd,
		"--output-last-message",
		job.result_message_path,
	}

	if job.model then
		table.insert(command, 3, "--model")
		table.insert(command, 4, job.model)
	end
	if job.reasoning_effort then
		table.insert(command, 3, "-c")
		table.insert(command, 4, 'model_reasoning_effort="' .. job.reasoning_effort .. '"')
	end
	if job.thread_id then
		vim.list_extend(command, { "resume", job.thread_id })
	end
	table.insert(command, "-")

	return command
end

local function stop_completion_timer(job)
	local timer = job.completion_timer
	job.completion_timer = nil
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
end

local function stop_activity(job)
	if job.stop_activity then
		local stop = job.stop_activity
		job.stop_activity = nil
		stop()
	end
end

local function read_lines(path)
	if not path or vim.fn.filereadable(path) ~= 1 then
		return {}
	end
	return vim.fn.readfile(path)
end

local function trim_empty_edges(lines)
	local first = 1
	local last = #lines
	while first <= last and lines[first] == "" do
		first = first + 1
	end
	while last >= first and lines[last] == "" do
		last = last - 1
	end

	local result = {}
	for index = first, last do
		table.insert(result, lines[index])
	end
	return result
end

local function parse_json_events(lines)
	local thread_id = nil
	local fallback_answer = nil
	for _, line in ipairs(lines or {}) do
		if line ~= "" then
			local ok, event = pcall(vim.json.decode, line)
			if ok and type(event) == "table" then
				if event.type == "thread.started" and type(event.thread_id) == "string" then
					thread_id = event.thread_id
				end
				local item = event.item
				if
					event.type == "item.completed"
					and type(item) == "table"
					and item.type == "agent_message"
					and type(item.text) == "string"
				then
					fallback_answer = vim.split(item.text, "\n", { plain = true })
				end
			end
		end
	end
	return thread_id, fallback_answer
end

local function cleanup_job_files(job)
	for _, path in ipairs({
		job.prompt_path,
		job.stdout_path,
		job.stderr_path,
		job.status_path,
		job.result_message_path,
		job.snapshot_path,
	}) do
		if path then
			pcall(vim.fn.delete, path)
		end
	end
end

local function finish(job, code, stdout_lines, stderr_lines)
	if not job or job.finished_at then
		return
	end

	stop_completion_timer(job)
	stop_activity(job)
	stdout_lines = stdout_lines or read_lines(job.stdout_path)
	stderr_lines = trim_empty_edges(stderr_lines or read_lines(job.stderr_path))
	local captured_thread_id, fallback_answer = parse_json_events(stdout_lines)
	local answer_lines = trim_empty_edges(read_lines(job.result_message_path))
	if #answer_lines == 0 and fallback_answer then
		answer_lines = trim_empty_edges(fallback_answer)
	end
	cleanup_job_files(job)
	local status = job.cancel_requested and "cancelled" or (code == 0 and "success" or "failed")
	M.update(job, {
		answer_lines = answer_lines,
		exit_code = code,
		finished_at = os.time(),
		stderr_lines = stderr_lines,
		status = status,
		thread_id = captured_thread_id or job.thread_id,
	})

	local level = (status == "success" or status == "cancelled") and vim.log.levels.INFO or vim.log.levels.WARN
	util.notify(
		"Ephemeral Codex "
			.. job.action
			.. " "
			.. status
			.. " with model "
			.. model.display(job.model)
			.. " and code "
			.. code
			.. ". Open the result with :CodexJobs.",
		level
	)
end

local function fail_to_start(job, message)
	if not job or job.finished_at then
		return
	end
	stop_completion_timer(job)
	stop_activity(job)
	cleanup_job_files(job)
	M.update(job, {
		stderr_lines = message and message ~= "" and { message } or {},
		finished_at = os.time(),
		status = "failed_to_start",
	})
	local suffix = message and message ~= "" and ": " .. message or ""
	util.notify("Failed to start ephemeral Codex " .. job.action .. " job" .. suffix, vim.log.levels.ERROR)
end

local function run_direct(job, prompt)
	job.transport = "direct"
	job.result_message_path = vim.fn.tempname() .. ".message"
	local stdout_lines = {}
	local stderr_lines = {}
	local job_id = vim.fn.jobstart(M.command_args(job), {
		stdin = "pipe",
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if data then
				vim.list_extend(stdout_lines, data)
			end
		end,
		on_stderr = function(_, data)
			if data then
				vim.list_extend(stderr_lines, data)
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				finish(job, code, stdout_lines, stderr_lines)
			end)
		end,
	})

	if job_id <= 0 then
		fail_to_start(job)
		return
	end

	M.update(job, {
		job_id = job_id,
		status = "running",
	})
	vim.fn.chansend(job_id, prompt)
	vim.fn.chanclose(job_id, "stdin")
end

function M.run(action, target, instruction)
	if instruction == nil or instruction:match("^%s*$") then
		return
	end

	if vim.fn.executable("codex") ~= 1 then
		util.notify("codex executable was not found on PATH", vim.log.levels.ERROR)
		return
	end
	if action == "edit" and target.modified == "yes" then
		util.notify("Save the buffer before running ephemeral Codex edits", vim.log.levels.WARN)
		return
	end

	local selected_model = state.ephemeral_models[action]
	local prompt = build_ephemeral_prompt(action, instruction, target)
	local job_record = M.create(action, target, selected_model, instruction)
	local stop_spinner = spinner.start_spinner(action, target, job_record)
	local stop_diagnostic = spinner.start_diagnostic(action, target, job_record)
	job_record.reasoning_effort = action == "command" and constants.EPHEMERAL_COMMAND_REASONING_EFFORT or nil
	job_record.stop_activity = function()
		stop_spinner()
		stop_diagnostic()
	end

	util.notify(
		"Started ephemeral Codex "
			.. action
			.. " over "
			.. target.kind
			.. " with model "
			.. model.display(selected_model)
	)

	run_direct(job_record, prompt)
end

local function active_thread_job(thread_id)
	for _, candidate in pairs(state.ephemeral_jobs) do
		if candidate.thread_id == thread_id and M.is_active(candidate) then
			return candidate
		end
	end
	return nil
end

function M.follow_up(job, instruction)
	if not job or not job.finished_at then
		util.notify("Select a completed Codex job to follow up", vim.log.levels.WARN)
		return false
	end
	if not job.thread_id then
		util.notify("Codex thread ID was not captured; this result cannot be resumed", vim.log.levels.WARN)
		return false
	end
	if instruction == nil or instruction:match("^%s*$") then
		return false
	end
	if vim.fn.executable("codex") ~= 1 then
		util.notify("codex executable was not found on PATH", vim.log.levels.ERROR)
		return false
	end

	local active = active_thread_job(job.thread_id)
	if active then
		util.notify("Codex thread already has running job #" .. active.id, vim.log.levels.WARN)
		return false
	end

	local next_job = M.create(job.action, job.target, job.model, instruction, {
		cwd = job.cwd,
		parent_job_id = job.id,
		reasoning_effort = job.reasoning_effort,
		sandbox = job.sandbox,
		thread_id = job.thread_id,
	})
	local stop_spinner = spinner.start_spinner(next_job.action, next_job.target, next_job)
	local stop_diagnostic = spinner.start_diagnostic(next_job.action, next_job.target, next_job)
	next_job.stop_activity = function()
		stop_spinner()
		stop_diagnostic()
	end

	util.notify("Resuming Codex thread from job #" .. job.id .. " as job #" .. next_job.id)
	run_direct(next_job, instruction)
	return true
end

function M.prompt_follow_up(job)
	if not job or not job.finished_at then
		util.notify("Select a completed Codex job to follow up", vim.log.levels.WARN)
		return
	end
	if not job.thread_id then
		util.notify("Codex thread ID was not captured; this result cannot be resumed", vim.log.levels.WARN)
		return
	end

	vim.ui.input({ prompt = "Codex follow-up: " }, function(instruction)
		M.follow_up(job, instruction)
	end)
end

function M.cancel(job)
	if not job or not M.is_active(job) then
		util.notify("No running Codex job under cursor", vim.log.levels.WARN)
		return false
	end

	job.cancel_requested = true
	M.update(job, { status = "cancelling" })
	if job.job_id then
		vim.fn.jobstop(job.job_id)
	else
		job.cancel_requested = false
		M.update(job, { status = "running" })
		util.notify("Codex job #" .. job.id .. " is not ready to cancel", vim.log.levels.WARN)
		return false
	end

	util.notify("Cancelling Codex job #" .. job.id)
	return true
end

function M.prompt_and_run(action, target, input_prompt)
	if not target then
		return
	end

	local prompt = input_prompt or (action == "edit" and "Codex edit: " or "Codex command: ")
	vim.ui.input({ prompt = prompt }, function(instruction)
		M.run(action, target, instruction)
	end)
end

return M
