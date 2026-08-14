local constants = require("codex.constants")
local state = require("codex.state")
local herdr = require("codex.herdr")
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

function M.create(action, target, selected_model, instruction)
	local id = state.next_ephemeral_job_id
	state.next_ephemeral_job_id = state.next_ephemeral_job_id + 1

	local job = {
		id = id,
		action = action,
		cancel_requested = false,
		completion_timer = nil,
		cwd = vim.fn.getcwd(),
		exit_code = nil,
		finished_at = nil,
		herdr_pane_id = nil,
		herdr_tab_id = nil,
		herdr_workspace_id = nil,
		instruction = instruction,
		job_id = nil,
		kind = target.kind,
		model = selected_model,
		path = target.path,
		prompt_path = nil,
		reasoning_effort = nil,
		result_path = nil,
		sandbox = action == "edit" and "workspace-write" or "read-only",
		snapshot_path = target.snapshot_path,
		start_line = target.start_line,
		started_at = os.time(),
		status = "starting",
		status_path = nil,
		stderr_path = nil,
		stdout_path = nil,
		stop_activity = nil,
		target = target,
		end_line = target.end_line,
		transport = nil,
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

local function get_ephemeral_result_dir()
	local tmp_dir = (vim.uv or vim.loop).os_tmpdir()
	local result_dir = tmp_dir .. "/" .. constants.EPHEMERAL_RESULT_SUBDIR
	local ok = pcall(vim.fn.mkdir, result_dir, "p")

	if ok and vim.fn.isdirectory(result_dir) == 1 then
		return result_dir
	end

	return tmp_dir
end

local function next_ephemeral_result_path()
	local id = state.next_ephemeral_result_id
	state.next_ephemeral_result_id = state.next_ephemeral_result_id + 1

	return string.format("%s/codex-ephemeral-%s-%03d.md", get_ephemeral_result_dir(), os.date("%Y%m%d-%H%M%S"), id)
end

local function write_result_file(lines)
	local path = next_ephemeral_result_path()
	local ok = vim.fn.writefile(lines, path)

	if ok ~= 0 then
		util.notify("Failed to write ephemeral Codex result: " .. path, vim.log.levels.ERROR)
		return nil
	end

	return path
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
		"",
		"Target: " .. target.kind,
	}

	vim.list_extend(lines, target.context_lines)

	return table.concat(lines, "\n")
end

local function make_result_lines(action, instruction, target, selected_model, exit_code, stdout_lines, stderr_lines)
	local lines = {
		"# Codex Ephemeral Result",
		"",
		"- Action: " .. action,
		"- Target: " .. target.kind,
		"- Model: " .. model.display(selected_model),
		"- Exit code: " .. exit_code,
		"- File: " .. target.path,
		"- Lines: " .. target.start_line .. "-" .. target.end_line,
		"",
		"## Instruction",
		"",
		instruction,
		"",
		"## Stdout",
		"",
	}
	vim.list_extend(lines, stdout_lines)
	vim.list_extend(lines, {
		"",
		"## Stderr",
		"",
	})
	vim.list_extend(lines, stderr_lines)

	return lines
end

function M.command_args(job)
	local command = {
		"codex",
		"exec",
		"--ephemeral",
		"--sandbox",
		job.sandbox,
		"--cd",
		job.cwd,
		"-",
	}

	if job.model then
		table.insert(command, 3, "--model")
		table.insert(command, 4, job.model)
	end
	if job.reasoning_effort then
		table.insert(command, 3, "-c")
		table.insert(command, 4, 'model_reasoning_effort="' .. job.reasoning_effort .. '"')
	end

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

local function cleanup_job_files(job)
	for _, path in ipairs({
		job.prompt_path,
		job.stdout_path,
		job.stderr_path,
		job.status_path,
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
	stderr_lines = stderr_lines or read_lines(job.stderr_path)
	local result_path = write_result_file(
		make_result_lines(job.action, job.instruction, job.target, job.model, code, stdout_lines, stderr_lines)
	)
	cleanup_job_files(job)
	local status = job.cancel_requested and "cancelled" or (code == 0 and "success" or "failed")
	M.update(job, {
		exit_code = code,
		finished_at = os.time(),
		result_path = result_path,
		status = status,
	})

	local level = (status == "success" or status == "cancelled") and vim.log.levels.INFO or vim.log.levels.WARN
	local suffix = result_path and ": " .. vim.fn.fnamemodify(result_path, ":~") or ""
	util.notify(
		"Ephemeral Codex "
			.. job.action
			.. " "
			.. status
			.. " with model "
			.. model.display(job.model)
			.. " and code "
			.. code
			.. suffix,
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
		finished_at = os.time(),
		status = "failed_to_start",
	})
	local suffix = message and message ~= "" and ": " .. message or ""
	util.notify("Failed to start ephemeral Codex " .. job.action .. " job" .. suffix, vim.log.levels.ERROR)
end

local function prepare_herdr_files(job, prompt)
	local stem = vim.fn.tempname()
	job.prompt_path = stem .. ".prompt"
	job.stdout_path = stem .. ".stdout"
	job.stderr_path = stem .. ".stderr"
	job.status_path = stem .. ".status"
	local lines = vim.split(prompt, "\n", { plain = true })
	return vim.fn.writefile(lines, job.prompt_path, "b") == 0
end

local function check_herdr_completion(job)
	if job.finished_at or not job.status_path or vim.fn.filereadable(job.status_path) ~= 1 then
		return false
	end
	local status_lines = vim.fn.readfile(job.status_path, "", 1)
	local code = tonumber(status_lines[1])
	if not code then
		return false
	end
	finish(job, code)
	return true
end

local function start_herdr_completion_poll(job)
	if check_herdr_completion(job) then
		return
	end
	local timer = vim.uv.new_timer()
	job.completion_timer = timer
	timer:start(100, 200, function()
		vim.schedule(function()
			check_herdr_completion(job)
		end)
	end)
end

local function run_in_herdr(job, prompt)
	job.transport = "herdr"
	job.herdr_workspace_id = vim.env.HERDR_WORKSPACE_ID
	if not prepare_herdr_files(job, prompt) then
		fail_to_start(job, "could not write prompt state")
		return
	end

	herdr.launch_ephemeral(job, {
		on_error = function(_, message)
			fail_to_start(job, message)
		end,
		on_success = function()
			M.update(job, { status = "running" })
			start_herdr_completion_poll(job)
		end,
	})
end

local function run_direct(job, prompt)
	job.transport = "direct"
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

	if herdr.ephemeral_available() then
		run_in_herdr(job_record, prompt)
	else
		run_direct(job_record, prompt)
	end
end

function M.cancel(job)
	if not job or not M.is_active(job) then
		util.notify("No running Codex job under cursor", vim.log.levels.WARN)
		return false
	end

	job.cancel_requested = true
	M.update(job, { status = "cancelling" })
	if job.transport == "herdr" and job.herdr_tab_id then
		herdr.close_tab(job, {
			on_success = function()
				if not check_herdr_completion(job) then
					finish(job, 130)
				end
			end,
			on_error = function(_, message)
				if check_herdr_completion(job) then
					return
				end
				job.cancel_requested = false
				M.update(job, { status = "running" })
				util.notify("Failed to cancel Codex job #" .. job.id .. ": " .. message, vim.log.levels.ERROR)
			end,
		})
	elseif job.job_id then
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
