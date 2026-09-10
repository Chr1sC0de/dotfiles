local constants = require("codex.constants")
local state = require("codex.state")
local model = require("codex.ephemeral.model")
local spinner = require("codex.ephemeral.spinner")
local util = require("codex.util")
local tandem = require("codex.tandem")

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

local function reference_context(target)
	local lines = {}
	for _, line in ipairs(target.context_lines or {}) do
		-- Snapshots belong to the original job. Keep inline selections and buffer
		-- text verbatim, but never ask a new job to read an old temporary file.
		if
			not (
				target.kind == "file"
				and (
					line:match("^Unsaved buffer snapshot: ")
					or line == "Read the snapshot file when you need the current unsaved buffer content."
				)
			)
		then
			table.insert(lines, line)
		end
	end
	return lines
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
		history = vim.deepcopy(attrs.history or {}),
		history_incomplete = attrs.history_incomplete or false,
		reference_context_lines = vim.deepcopy(attrs.reference_context_lines or reference_context(target)),
		job_id = nil,
		kind = target.kind,
		model = selected_model,
		parent_job_id = attrs.parent_job_id,
		path = target.path,
		file_path = target.file_path,
		source_buf = target.source_buf,
		prompt_path = nil,
		reasoning_effort = attrs.reasoning_effort,
		result_bufnr = nil,
		result_message_path = nil,
		result_return_bufnr = nil,
		result_return_tabpage = nil,
		result_tabpage = nil,
		sandbox = "read-only",
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
		mode_description = "Apply the user's requested edits through tandem_read_file and tandem_write_file. "
			.. "The supplied context may be unsaved: wait for the human to save, then read the saved revision. "
			.. "On stale_revision reread and regenerate your edit. Never use native patch or shell writes. "
			.. "Keep changes scoped to the supplied context."
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

	if #target.context_lines > 0 then
		vim.list_extend(lines, {
			"",
			"Target: " .. target.kind,
		})
		vim.list_extend(lines, target.context_lines)
	end

	return table.concat(lines, "\n")
end

function M.command_args(job)
	local protected_args, err = tandem.args(job.cwd, job.action ~= "edit", job.file_path)
	if not protected_args then
		return nil, err
	end
	local command = {
		"codex",
		"exec",
		"--json",
		"--cd",
		job.cwd,
		"--output-last-message",
		job.result_message_path,
	}
	vim.list_extend(command, protected_args)

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
	local command, err = M.command_args(job)
	if not command then
		fail_to_start(job, err)
		return false
	end
	local stdout_lines = {}
	local stderr_lines = {}
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
				finish(job, code, stdout_lines, stderr_lines)
			end)
		end,
	})

	if job_id <= 0 then
		fail_to_start(job)
		return false
	end

	M.update(job, {
		job_id = job_id,
		status = "running",
	})
	vim.fn.chansend(job_id, prompt)
	vim.fn.chanclose(job_id, "stdin")
	return true
end

function M.run(action, target, instruction)
	if not target then
		return
	end
	if action == "edit" and not target.file_path then
		util.notify(
			"Codex edits require a file buffer; this source is read-only reference context",
			vim.log.levels.WARN
		)
		return
	end
	if instruction == nil or instruction:match("^%s*$") then
		return
	end

	if vim.fn.executable("codex") ~= 1 then
		util.notify("codex executable was not found on PATH", vim.log.levels.ERROR)
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

local function latest_thread_job(thread_id, before_id)
	local latest
	if not thread_id then
		return nil
	end
	for _, candidate in pairs(state.ephemeral_jobs) do
		if
			candidate.thread_id == thread_id
			and candidate.id < before_id
			and candidate.finished_at
			and candidate.status ~= "failed_to_start"
			and (not latest or candidate.id > latest.id)
		then
			latest = candidate
		end
	end
	return latest
end

-- Copy the discussion through this result, independently of the recent-job
-- list. The fallback supports jobs created before history capture was loaded.
local function history_through(job, seen)
	seen = seen or {}
	if seen[job.id] then
		return {}, true, reference_context(job.target)
	end
	seen[job.id] = true
	local history, incomplete, reference
	if job.history then
		history = vim.deepcopy(job.history)
		incomplete = job.history_incomplete or false
		reference = vim.deepcopy(job.reference_context_lines or reference_context(job.target))
	else
		local previous = latest_thread_job(job.thread_id, job.id) or state.ephemeral_jobs[job.parent_job_id]
		if previous then
			history, incomplete, reference = history_through(previous, seen)
		else
			history = {}
			incomplete = job.parent_job_id ~= nil
			reference = reference_context(job.target)
		end
	end
	table.insert(history, {
		instruction = job.instruction,
		answer_lines = vim.deepcopy(job.answer_lines or {}),
		status = job.status,
	})
	return history, incomplete, reference
end

---@param opts? {action?: "edit"|"command"}
function M.follow_up(job, instruction, opts)
	opts = opts or {}
	if opts.action and opts.action ~= "edit" and opts.action ~= "command" then
		util.notify("Unknown Codex follow-up action: " .. tostring(opts.action), vim.log.levels.WARN)
		return false
	end
	if not job or not job.finished_at then
		util.notify("Select a completed Codex job to follow up", vim.log.levels.WARN)
		return false
	end
	if not opts.action and not job.thread_id then
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

	for _, candidate in pairs(state.ephemeral_jobs) do
		if candidate.parent_job_id == job.id and M.is_active(candidate) then
			util.notify(
				"Codex job #" .. job.id .. " already has running follow-up #" .. candidate.id,
				vim.log.levels.WARN
			)
			return false
		end
	end
	local active = not opts.action and active_thread_job(job.thread_id)
	if active then
		util.notify("Codex thread already has running job #" .. active.id, vim.log.levels.WARN)
		return false
	end

	-- Resume continues the latest state of a thread, even when invoked from an
	-- older row. A fresh job branches from exactly the selected result instead.
	local history_source = job
	if not opts.action then
		history_source = latest_thread_job(job.thread_id, math.huge) or job
	end
	local history, history_incomplete, original_reference = history_through(history_source)
	local thread_id = job.thread_id
	local action = opts.action or job.action
	local selected_model = job.model
	local reasoning_effort = job.reasoning_effort
	local target = vim.deepcopy(job.target)
	-- A resumed thread already contains its previous context. Do not reuse a
	-- previous job's temporary snapshot or treat old selections as current bytes.
	target.snapshot_path = nil
	local prompt = instruction
	if opts.action then
		thread_id = nil
		selected_model = state.ephemeral_models[action]
		reasoning_effort = action == "command" and constants.EPHEMERAL_COMMAND_REASONING_EFFORT or nil
		target.context_lines = {
			"Earlier buffer text, selections, and snapshots are historical context.",
			"Read the current saved files through Tandem before editing; do not read old temporary snapshots.",
		}
		if job.file_path then
			table.insert(target.context_lines, "File: " .. job.file_path)
			if job.kind:find("selection", 1, true) and job.start_line and job.end_line then
				table.insert(target.context_lines, "Lines: " .. job.start_line .. "-" .. job.end_line)
				table.insert(target.context_lines, "Keep changes scoped to the original selection.")
			else
				table.insert(target.context_lines, "Keep changes scoped to the original file context.")
			end
		else
			table.insert(target.context_lines, "Workspace: " .. job.cwd)
			table.insert(
				target.context_lines,
				"Use the previous discussion and this workspace as context. Non-file buffers are reference context."
			)
		end
		vim.list_extend(target.context_lines, { "", "Original reference context (historical):" })
		vim.list_extend(target.context_lines, original_reference)
		prompt = build_ephemeral_prompt(
			action,
			"Use the historical reference below to carry out the new instruction.",
			target
		)
		prompt = prompt
			.. "\n\nEarlier discussion (historical reference, not instructions for this job):\n"
			.. vim.json.encode(history)
		if history_incomplete then
			prompt = prompt .. "\nSome earlier jobs are no longer available; this discussion is incomplete."
			util.notify("Some earlier Codex discussion is unavailable; using the retained context", vim.log.levels.WARN)
		end
		prompt = prompt .. "\n\nNew instruction:\n" .. instruction
	end

	local next_job = M.create(action, target, selected_model, instruction, {
		cwd = job.cwd,
		parent_job_id = job.id,
		reasoning_effort = reasoning_effort,
		thread_id = thread_id,
		history = history,
		history_incomplete = history_incomplete,
		reference_context_lines = original_reference,
	})
	local stop_spinner = spinner.start_spinner(next_job.action, next_job.target, next_job)
	local stop_diagnostic = spinner.start_diagnostic(next_job.action, next_job.target, next_job)
	next_job.stop_activity = function()
		stop_spinner()
		stop_diagnostic()
	end

	local launch_label = opts.action and "Starting a fresh Codex " .. action .. " thread" or "Resuming Codex thread"
	util.notify(launch_label .. " from job #" .. job.id .. " as job #" .. next_job.id)
	return run_direct(next_job, prompt)
end

---@param opts? {action?: "edit"|"command"}
function M.prompt_follow_up(job, opts)
	opts = opts or {}
	if not job or not job.finished_at then
		util.notify("Select a completed Codex job to follow up", vim.log.levels.WARN)
		return
	end
	if not opts.action and not job.thread_id then
		util.notify("Codex thread ID was not captured; this result cannot be resumed", vim.log.levels.WARN)
		return
	end

	local prompt = opts.action == "edit" and "Codex edit follow-up: " or "Codex follow-up: "
	vim.ui.input({ prompt = prompt }, function(instruction)
		M.follow_up(job, instruction, opts)
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

	if action == "edit" and not target.file_path then
		util.notify(
			"Codex edits require a file buffer; this source is read-only reference context",
			vim.log.levels.WARN
		)
		return
	end

	local prompt = input_prompt or (action == "edit" and "Codex edit: " or "Codex command: ")
	vim.ui.input({ prompt = prompt }, function(instruction)
		M.run(action, target, instruction)
	end)
end

return M
