local prompts = require("workmux.prompts")
local util = require("workmux.util")

local M = { _test = {} }
local SHELL_READY_ATTEMPTS = 40
local SHELL_READY_DELAY_MS = 100

local function command_error(result)
	local message = util.trim(result.stderr)
	if message == "" then
		message = util.trim(result.stdout)
	end
	if message == "" then
		message = "exit code " .. tostring(result.code)
	end
	return message
end

local function run(args, opts)
	opts = opts or {}
	if M._test.run then
		M._test.run(args, opts)
		return
	end

	vim.system(
		vim.list_extend({ "herdr" }, args),
		{ text = true },
		vim.schedule_wrap(function(result)
			if result.code == 0 then
				if opts.on_success then
					opts.on_success(result)
				end
				return
			end
			if opts.on_error then
				opts.on_error(result, command_error(result))
			else
				util.notify("Herdr command failed: " .. command_error(result), vim.log.levels.ERROR)
			end
		end)
	)
end

local function decode_result(result, description)
	local ok, envelope = pcall(vim.json.decode, result.stdout or "")
	if not ok or type(envelope) ~= "table" or type(envelope.result) ~= "table" then
		return nil, "invalid Herdr " .. description .. " response"
	end
	return envelope.result
end

local function fail_step(step, message)
	util.notify("Herdr " .. step .. " failed: " .. tostring(message), vim.log.levels.ERROR)
end

local function current_cwd()
	return vim.fn.getcwd()
end

local function workspace_checkout(workspace, fallback)
	local worktree = type(workspace) == "table" and workspace.worktree or nil
	return (worktree and (worktree.checkout_path or worktree.path))
		or (type(workspace) == "table" and workspace.cwd)
		or fallback
end

local function workspace_label(branch)
	local label = branch:gsub("[^%w._-]+", "-"):gsub("^-+", ""):gsub("-+$", "")
	return label ~= "" and label or "worktree"
end

local function agent_name(cwd)
	return "worktree-" .. vim.fn.sha256(cwd):sub(1, 12)
end

local function focus_workspace(workspace_id)
	run({ "workspace", "focus", workspace_id }, {
		on_error = function(_, message)
			fail_step("workspace focus", message)
		end,
	})
end

local function focus_agent(name)
	run({ "agent", "focus", name }, {
		on_error = function(_, message)
			fail_step("agent focus", message)
		end,
	})
end

local function parse_workspace_result(result, description)
	local payload, err = decode_result(result, description)
	if not payload then
		return nil, nil, nil, err
	end
	local workspace = payload.workspace
	if type(workspace) ~= "table" or type(workspace.workspace_id) ~= "string" then
		return nil, nil, nil, "Herdr " .. description .. " response did not include a workspace"
	end
	local path = workspace_checkout(workspace, nil)
	if type(payload.worktree) == "table" then
		path = payload.worktree.checkout_path or payload.worktree.path or path
	end
	return workspace, path, payload.already_open == true
end

local function list_root_pane(workspace_id, callback)
	run({ "pane", "list", "--workspace", workspace_id }, {
		on_error = function(_, message)
			fail_step("pane discovery", message)
		end,
		on_success = function(result)
			local payload, err = decode_result(result, "pane list")
			local panes = payload and payload.panes or nil
			if type(panes) ~= "table" or #panes ~= 1 or type(panes[1].pane_id) ~= "string" then
				fail_step("pane discovery", err or "new workspace did not contain exactly one root pane")
				return
			end
			callback(panes[1].pane_id)
		end,
	})
end

local function shell_is_ready(info)
	if type(info) ~= "table" or type(info.shell_pid) ~= "number" then
		return false
	end
	if info.foreground_process_group_id == info.shell_pid then
		return true
	end
	for _, process in ipairs(info.foreground_processes or {}) do
		if process.pid == info.shell_pid then
			return true
		end
	end
	return false
end

local function wait_for_shell(pane_id, callback, attempt)
	attempt = attempt or 1
	local function retry(message)
		if attempt >= SHELL_READY_ATTEMPTS then
			fail_step("Codex shell readiness", message or "timed out waiting for the root shell")
			return
		end
		vim.defer_fn(function()
			wait_for_shell(pane_id, callback, attempt + 1)
		end, SHELL_READY_DELAY_MS)
	end

	run({ "pane", "process-info", "--pane", pane_id }, {
		on_error = function(_, message)
			retry(message)
		end,
		on_success = function(result)
			local payload, err = decode_result(result, "pane process info")
			local info = payload and payload.process_info or nil
			if shell_is_ready(info) then
				callback()
				return
			end
			retry(err)
		end,
	})
end

local function start_agent_when_available(workspace_id, pane_id, cwd, opts, attempt)
	attempt = attempt or 1
	local name = agent_name(cwd)
	local function finish_start()
		if opts.focus then
			focus_agent(name)
			return
		end
		local label = vim.fn.fnamemodify(cwd, ":t")
		util.notify("Codex job started" .. (label ~= "" and (" in " .. label) or ""))
	end
	local args = {
		"agent",
		"start",
		name,
		"--kind",
		"codex",
		"--pane",
		pane_id,
		"--timeout",
		"60000",
		"--",
	}
	if opts.resume then
		vim.list_extend(args, { "resume", "--last", "--cd", cwd })
	else
		vim.list_extend(args, { "--cd", cwd })
	end

	wait_for_shell(pane_id, function()
		run(args, {
			on_error = function(_, message)
				local pane_busy = tostring(message or ""):find("agent_pane_busy", 1, true) ~= nil
				if pane_busy and attempt < SHELL_READY_ATTEMPTS then
					vim.defer_fn(function()
						start_agent_when_available(workspace_id, pane_id, cwd, opts, attempt + 1)
					end, SHELL_READY_DELAY_MS)
					return
				end
				fail_step("Codex start", message)
				if opts.focus then
					focus_workspace(workspace_id)
				end
			end,
			on_success = function()
				if opts.prompt == nil then
					finish_start()
					return
				end
				run({ "agent", "prompt", name, opts.prompt }, {
					on_error = function(_, message)
						fail_step("initial prompt", message)
						if opts.focus then
							focus_agent(name)
						end
					end,
					on_success = function()
						finish_start()
					end,
				})
			end,
		})
	end)
end

local function workspace_context(workspace, checkout)
	local workspace_id = workspace.workspace_id
	local cwd = workspace_checkout(workspace, checkout)
	if type(cwd) ~= "string" or cwd == "" then
		fail_step("layout", "workspace response did not include a checkout path")
		return nil, nil
	end
	return workspace_id, cwd
end

local function bootstrap_agent_workspace(workspace, checkout, opts)
	local workspace_id, cwd = workspace_context(workspace, checkout)
	if not workspace_id then
		return
	end

	list_root_pane(workspace_id, function(root_pane_id)
		util.notify("starting Codex in the worktree...")
		start_agent_when_available(workspace_id, root_pane_id, cwd, opts)
	end)
end

local function bootstrap_editor_workspace(workspace, checkout)
	local workspace_id, cwd = workspace_context(workspace, checkout)
	if not workspace_id then
		return
	end

	list_root_pane(workspace_id, function(root_pane_id)
		util.notify("starting Neovim in the worktree...")
		wait_for_shell(root_pane_id, function()
			run({ "pane", "run", root_pane_id, "nvim ." }, {
				on_error = function(_, message)
					fail_step("Neovim start", message)
				end,
				on_success = function()
					focus_workspace(workspace_id)
				end,
			})
		end)
	end)
end

local function validate_branch(branch, callback)
	if M._test.validate_branch then
		M._test.validate_branch(branch, callback)
		return
	end
	vim.system(
		{ "git", "check-ref-format", "--branch", branch },
		{ cwd = current_cwd(), text = true },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 then
				util.notify("invalid branch name: " .. branch, vim.log.levels.ERROR)
				return
			end
			callback(branch)
		end)
	)
end

local function create_worktree(branch, opts)
	util.notify("creating Herdr worktree " .. branch .. "...")
	run({
		"worktree",
		"create",
		"--cwd",
		current_cwd(),
		"--branch",
		branch,
		"--label",
		workspace_label(branch),
		"--no-focus",
	}, {
		on_error = function(_, message)
			fail_step("worktree creation", message)
		end,
		on_success = function(result)
			local workspace, checkout, _, err = parse_workspace_result(result, "worktree creation")
			if not workspace then
				fail_step("worktree creation", err)
				return
			end
			if opts.editor then
				bootstrap_editor_workspace(workspace, checkout)
			else
				bootstrap_agent_workspace(workspace, checkout, opts)
			end
		end,
	})
end

local function generate_branch(task, callback)
	if M._test.generate_branch then
		M._test.generate_branch(task, callback)
		return
	end
	local instruction = table.concat({
		"Generate a concise lowercase kebab-case Git branch name for this task.",
		"Output only the branch name, with no Markdown or explanation.",
		"",
		task,
	}, "\n")
	util.notify("generating branch name...")
	vim.system(
		{
			"codex",
			"exec",
			"--ephemeral",
			"--color",
			"never",
			"--config",
			'model_reasoning_effort="xhigh"',
			"-m",
			"gpt-5.5",
			instruction,
		},
		{ text = true },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 then
				fail_step("branch-name generation", command_error(result))
				return
			end
			local branch = util.trim(result.stdout)
			if branch == "" or branch:find("\n", 1, true) then
				fail_step("branch-name generation", "Codex did not return one branch name")
				return
			end
			callback(branch)
		end)
	)
end

local function list_worktrees(callback)
	run({ "worktree", "list", "--cwd", current_cwd() }, {
		on_error = function(_, message)
			fail_step("worktree list", message)
		end,
		on_success = function(result)
			local payload, err = decode_result(result, "worktree list")
			local items = payload and payload.worktrees or nil
			if type(items) ~= "table" then
				fail_step("worktree list", err or "response did not include worktrees")
				return
			end
			callback(items, payload.source)
		end,
	})
end

local function worktree_item_label(item)
	local label = item.label or item.branch or item.path or "unknown"
	local state = {}
	if item.is_linked_worktree ~= true then
		table.insert(state, "main")
	end
	if item.open_workspace_id then
		table.insert(state, "open")
	else
		table.insert(state, "closed")
	end
	return label .. " [" .. table.concat(state, ", ") .. "]"
end

local function select_worktree(opts, callback)
	list_worktrees(function(items)
		local choices = {}
		for _, item in ipairs(items) do
			if
				(not opts.linked_only or item.is_linked_worktree == true)
				and (not opts.open_only or item.open_workspace_id ~= nil)
			then
				table.insert(choices, item)
			end
		end
		if #choices == 0 then
			util.notify(opts.empty_message or "no matching Herdr worktrees", vim.log.levels.WARN)
			return
		end
		vim.ui.select(choices, { prompt = opts.prompt, format_item = worktree_item_label }, function(choice)
			if choice then
				callback(choice)
			end
		end)
	end)
end

local function list_agents(callback)
	run({ "agent", "list" }, {
		on_error = function(_, message)
			fail_step("agent list", message)
		end,
		on_success = function(result)
			local payload, err = decode_result(result, "agent list")
			local agents = payload and payload.agents or nil
			if type(agents) ~= "table" then
				fail_step("agent list", err or "response did not include agents")
				return
			end
			callback(agents)
		end,
	})
end

function M.available()
	return vim.env.HERDR_ENV == "1"
		and vim.env.HERDR_WORKSPACE_ID ~= nil
		and vim.env.HERDR_WORKSPACE_ID ~= ""
		and vim.fn.executable("herdr") == 1
end

function M.add_prompt(task)
	generate_branch(task, function(branch)
		validate_branch(branch, function(valid_branch)
			create_worktree(valid_branch, { prompt = task, resume = false, focus = false })
		end)
	end)
end

function M.add_branch(branch)
	validate_branch(branch, function(valid_branch)
		create_worktree(valid_branch, { editor = true })
	end)
end

function M.open(resume)
	select_worktree({ prompt = resume and "Continue Herdr worktree" or "Open Herdr worktree" }, function(item)
		if item.open_workspace_id then
			focus_workspace(item.open_workspace_id)
			return
		end
		run({ "worktree", "open", "--cwd", current_cwd(), "--path", item.path, "--no-focus" }, {
			on_error = function(_, message)
				fail_step("worktree open", message)
			end,
			on_success = function(result)
				local workspace, checkout, already_open, err = parse_workspace_result(result, "worktree open")
				if not workspace then
					fail_step("worktree open", err)
					return
				end
				if already_open then
					focus_workspace(workspace.workspace_id)
					return
				end
				bootstrap_agent_workspace(workspace, checkout or item.path, { resume = resume, focus = true })
			end,
		})
	end)
end

function M.select_workspace()
	run({ "workspace", "list" }, {
		on_error = function(_, message)
			fail_step("workspace list", message)
		end,
		on_success = function(result)
			local payload, err = decode_result(result, "workspace list")
			local workspaces = payload and payload.workspaces or nil
			if type(workspaces) ~= "table" then
				fail_step("workspace list", err or "response did not include workspaces")
				return
			end
			vim.ui.select(workspaces, {
				prompt = "Herdr workspace",
				format_item = function(item)
					return (item.label or item.workspace_id) .. " [" .. (item.agent_status or "unknown") .. "]"
				end,
			}, function(choice)
				if choice then
					focus_workspace(choice.workspace_id)
				end
			end)
		end,
	})
end

function M.cycle_agent(direction)
	list_agents(function(agents)
		if #agents == 0 then
			util.notify("no Herdr agents found", vim.log.levels.WARN)
			return
		end
		local current = vim.env.HERDR_PANE_ID
		local index = nil
		for position, agent in ipairs(agents) do
			if agent.pane_id == current then
				index = position
				break
			end
		end
		if index == nil then
			index = direction > 0 and 0 or 1
		end
		local target_index = ((index - 1 + direction) % #agents) + 1
		focus_agent(agents[target_index].name or agents[target_index].pane_id)
	end)
end

function M.focus_latest_attention()
	list_agents(function(agents)
		local latest = nil
		for _, agent in ipairs(agents) do
			if agent.agent_status == "done" or agent.agent_status == "blocked" then
				if latest == nil or (agent.state_change_seq or 0) > (latest.state_change_seq or 0) then
					latest = agent
				end
			end
		end
		if latest == nil then
			util.notify("no done or blocked Herdr agents", vim.log.levels.WARN)
			return
		end
		focus_agent(latest.name or latest.pane_id)
	end)
end

function M.close()
	select_worktree({
		prompt = "Close Herdr workspace",
		linked_only = true,
		open_only = true,
		empty_message = "no open linked Herdr worktrees",
	}, function(item)
		run({ "workspace", "close", item.open_workspace_id }, {
			on_error = function(_, message)
				fail_step("workspace close", message)
			end,
		})
	end)
end

function M.remove()
	select_worktree({
		prompt = "Remove Herdr worktree",
		linked_only = true,
		open_only = true,
		empty_message = "no open linked Herdr worktrees to remove",
	}, function(item)
		local expected = item.branch or item.label or item.path
		prompts.confirm_exact(expected, "remove " .. expected, function()
			run({ "worktree", "remove", "--workspace", item.open_workspace_id }, {
				on_error = function(_, message)
					fail_step("worktree removal", message)
				end,
			})
		end)
	end)
end

function M.unsupported(action, alternative)
	util.notify(action .. " is Workmux-only in tmux; " .. alternative, vim.log.levels.WARN)
end

M._test.parse_workspace_result = parse_workspace_result
M._test.workspace_label = workspace_label
M._test.agent_name = agent_name
M._test.decode_result = decode_result
M._test.shell_is_ready = shell_is_ready

return M
