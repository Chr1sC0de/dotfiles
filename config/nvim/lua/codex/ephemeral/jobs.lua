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
		exit_code = nil,
		finished_at = nil,
		instruction = instruction,
		job_id = nil,
		kind = target.kind,
		model = selected_model,
		path = target.path,
		result_path = nil,
		start_line = target.start_line,
		started_at = os.time(),
		status = "starting",
		end_line = target.end_line,
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
	local state_dir = vim.fn.stdpath("state")
	local result_dir = state_dir .. "/" .. constants.EPHEMERAL_RESULT_SUBDIR
	local ok, created = pcall(vim.fn.mkdir, result_dir, "p")

	if (ok and created == 1) or vim.fn.isdirectory(result_dir) == 1 then
		return result_dir
	end

	return vim.fn.fnamemodify(vim.fn.tempname(), ":h")
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

function M.run(action, target, instruction)
	if instruction == nil or instruction:match("^%s*$") then
		return
	end

	if vim.fn.executable("codex") ~= 1 then
		util.notify("codex executable was not found on PATH", vim.log.levels.ERROR)
		return
	end

	local sandbox = action == "edit" and "workspace-write" or "read-only"
	local selected_model = state.ephemeral_models[action]
	local prompt = build_ephemeral_prompt(action, instruction, target)
	local stdout_lines = {}
	local stderr_lines = {}
	local job_record = M.create(action, target, selected_model, instruction)
	local stop_spinner = spinner.start_spinner(action, target, job_record)
	local stop_diagnostic = spinner.start_diagnostic(action, target, job_record)
	local function stop_activity()
		stop_spinner()
		stop_diagnostic()
	end
	local command = {
		"codex",
		"exec",
		"--ephemeral",
		"--sandbox",
		sandbox,
		"--cd",
		vim.fn.getcwd(),
		"-",
	}

	if selected_model then
		table.insert(command, 3, "--model")
		table.insert(command, 4, selected_model)
	end

	util.notify(
		"Started ephemeral Codex "
			.. action
			.. " over "
			.. target.kind
			.. " with model "
			.. model.display(selected_model)
	)

	local job_id = vim.fn.jobstart(command, {
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
				stop_activity()
				local result_path = write_result_file(
					make_result_lines(action, instruction, target, selected_model, code, stdout_lines, stderr_lines)
				)
				local status = job_record.cancel_requested and "cancelled" or (code == 0 and "success" or "failed")
				M.update(job_record, {
					exit_code = code,
					finished_at = os.time(),
					result_path = result_path,
					status = status,
				})

				local level = (status == "success" or status == "cancelled") and vim.log.levels.INFO
					or vim.log.levels.WARN
				local suffix = result_path and ": " .. vim.fn.fnamemodify(result_path, ":~") or ""
				util.notify(
					"Ephemeral Codex "
						.. action
						.. " "
						.. status
						.. " with model "
						.. model.display(selected_model)
						.. " and code "
						.. code
						.. suffix,
					level
				)
			end)
		end,
	})

	if job_id <= 0 then
		stop_activity()
		M.update(job_record, {
			finished_at = os.time(),
			status = "failed_to_start",
		})
		util.notify("Failed to start ephemeral Codex " .. action .. " job", vim.log.levels.ERROR)
		return
	end

	M.update(job_record, {
		job_id = job_id,
		status = "running",
	})
	vim.fn.chansend(job_id, prompt)
	vim.fn.chanclose(job_id, "stdin")
end

function M.prompt_and_run(action, target)
	if not target then
		return
	end

	local prompt = action == "edit" and "Codex edit: " or "Codex command: "
	vim.ui.input({ prompt = prompt }, function(instruction)
		M.run(action, target, instruction)
	end)
end

return M
