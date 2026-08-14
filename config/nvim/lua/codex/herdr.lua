local util = require("codex.util")

local M = {}

local AGENT_PREFIX = "nvim-codex-"
local LIFECYCLE_SUBDIR = "libexec/codex-herdr"
local ROUTE_SUBDIR = "codex/herdr"
local EPHEMERAL_LABEL_LIMIT = 64

local function herdr_binary()
	local configured = vim.env.HERDR_BIN_PATH
	if configured and configured ~= "" and vim.fn.executable(configured) == 1 then
		return configured
	end
	return "herdr"
end

local function state_dir()
	return util.join_path(vim.fn.stdpath("state"), ROUTE_SUBDIR)
end

local function executable_path(command)
	local path = vim.fn.exepath(command)
	if path and path ~= "" then
		return path
	end
	return command
end

function M.lifecycle_wrapper_dir()
	return util.join_path(vim.fn.stdpath("config"), LIFECYCLE_SUBDIR)
end

function M.ephemeral_runner_path()
	return util.join_path(M.lifecycle_wrapper_dir(), "ephemeral")
end

local function truncate_label(label)
	if vim.fn.strchars(label) <= EPHEMERAL_LABEL_LIMIT then
		return label
	end
	return vim.fn.strcharpart(label, 0, EPHEMERAL_LABEL_LIMIT - 1) .. "…"
end

function M.ephemeral_label(job)
	local action = job.action == "command" and "cmd" or tostring(job.action or "job")
	local path = tostring(job.path or "")
	local target = vim.fn.fnamemodify(path, ":t")
	if target == "" then
		target = "[No Name]"
	end
	local instruction = util.trim_whitespace(tostring(job.instruction or "")):gsub("%s+", " ")
	local prefix = string.format("%s #%s · %s", action, tostring(job.id or "?"), target)
	if instruction == "" then
		return truncate_label(prefix)
	end
	return truncate_label(prefix .. " · " .. instruction)
end

local function command_error(result)
	local message = util.trim_whitespace(result.stderr)
	if message == "" then
		message = util.trim_whitespace(result.stdout)
	end
	if message == "" then
		message = "exit code " .. tostring(result.code)
	end
	return message
end

local function run(args, opts)
	opts = opts or {}
	local argv = vim.list_extend({ herdr_binary() }, args)
	vim.system(
		argv,
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
			end
		end)
	)
end

function M.available()
	return vim.env.HERDR_ENV == "1"
		and vim.env.HERDR_WORKSPACE_ID ~= nil
		and vim.env.HERDR_WORKSPACE_ID ~= ""
		and vim.fn.executable(herdr_binary()) == 1
end

function M.ephemeral_available()
	return M.available() and vim.fn.executable(M.ephemeral_runner_path()) == 1
end

function M.agent_name(id)
	local pid = tostring(vim.fn.getpid()):gsub("[^0-9]", "")
	local suffix = tostring(id):gsub("[^a-zA-Z0-9_-]", "-"):lower()
	return (AGENT_PREFIX .. pid .. "-" .. suffix):sub(1, 32)
end

function M.route_path(agent_name)
	return util.join_path(state_dir(), agent_name .. ".route")
end

function M.write_route(session)
	if not session or not session.herdr_route_path then
		return false
	end
	if not session.hook_server or not session.hook_token or not session.id then
		return false
	end

	vim.fn.mkdir(state_dir(), "p", 448)
	local temporary = session.herdr_route_path .. ".tmp." .. tostring(vim.fn.getpid())
	local status = vim.fn.writefile({ session.hook_server, tostring(session.id), session.hook_token }, temporary, "s")
	if status ~= 0 then
		return false
	end
	pcall(vim.uv.fs_chmod, temporary, 384)
	local ok = vim.uv.fs_rename(temporary, session.herdr_route_path)
	if not ok then
		pcall(vim.fn.delete, temporary)
		return false
	end
	return true
end

function M.remove_route(session)
	if session and session.herdr_route_path then
		pcall(vim.fn.delete, session.herdr_route_path)
	end
end

function M.prepare(session, agent_name)
	session.launch_mode = "herdr"
	session.launch_status = "starting"
	session.codex_real_bin = executable_path("codex")
	session.herdr_real_bin = executable_path(herdr_binary())
	session.herdr_wrapper_dir = M.lifecycle_wrapper_dir()
	session.herdr_agent_name = agent_name or M.agent_name(session.id)
	session.herdr_route_path = M.route_path(session.herdr_agent_name)
	session.herdr_workspace_id = vim.env.HERDR_WORKSPACE_ID
	session.herdr_tab_label = "codex-" .. tostring(session.id)
	return M.write_route(session)
end

function M.tab_create_args(session, workspace_id)
	local current_path = vim.env.PATH or ""
	local wrapper_dir = session.herdr_wrapper_dir or M.lifecycle_wrapper_dir()
	local wrapped_path = wrapper_dir .. (current_path ~= "" and (":" .. current_path) or "")
	return {
		"tab",
		"create",
		"--workspace",
		workspace_id or session.herdr_workspace_id,
		"--cwd",
		session.cwd,
		"--label",
		session.herdr_tab_label,
		"--env",
		"CODEX_NVIM_STATE_FILE=" .. session.herdr_route_path,
		"--env",
		"CODEX_THREAD_ID=",
		"--env",
		"CODEX_REAL_BIN=" .. session.codex_real_bin,
		"--env",
		"CODEX_HERDR_BIN=" .. session.herdr_real_bin,
		"--env",
		"PATH=" .. wrapped_path,
		"--no-focus",
	}
end

function M.parse_tab_create(output)
	local ok, response = pcall(vim.json.decode, output or "")
	if not ok or type(response) ~= "table" or type(response.result) ~= "table" then
		return nil, nil, "invalid Herdr tab response"
	end
	local tab = response.result.tab
	local pane = response.result.root_pane
	if type(tab) ~= "table" or type(pane) ~= "table" or not tab.tab_id or not pane.pane_id then
		return nil, nil, "Herdr tab response did not include tab and pane ids"
	end
	return tab.tab_id, pane.pane_id
end

function M.ephemeral_tab_create_args(job)
	local env = {
		"CODEX_EPHEMERAL_PROMPT_PATH=" .. job.prompt_path,
		"CODEX_EPHEMERAL_STDOUT_PATH=" .. job.stdout_path,
		"CODEX_EPHEMERAL_STDERR_PATH=" .. job.stderr_path,
		"CODEX_EPHEMERAL_STATUS_PATH=" .. job.status_path,
		"CODEX_EPHEMERAL_SANDBOX=" .. job.sandbox,
		"CODEX_EPHEMERAL_MODEL=" .. (job.model or ""),
		"CODEX_EPHEMERAL_REASONING_EFFORT=" .. (job.reasoning_effort or ""),
		"CODEX_REAL_BIN=" .. executable_path("codex"),
		"CODEX_HERDR_BIN=" .. executable_path(herdr_binary()),
		"CODEX_THREAD_ID=",
	}
	local args = {
		"tab",
		"create",
		"--workspace",
		job.herdr_workspace_id,
		"--cwd",
		job.cwd,
		"--label",
		M.ephemeral_label(job),
	}
	for _, value in ipairs(env) do
		table.insert(args, "--env")
		table.insert(args, value)
	end
	table.insert(args, "--no-focus")
	return args
end

function M.ephemeral_pane_run_args(job)
	return {
		"pane",
		"run",
		job.herdr_pane_id,
		vim.fn.shellescape(M.ephemeral_runner_path()),
	}
end

function M.launch_ephemeral(job, opts)
	opts = opts or {}
	run(M.ephemeral_tab_create_args(job), {
		on_error = opts.on_error,
		on_success = function(result)
			local tab_id, pane_id, err = M.parse_tab_create(result.stdout)
			if not tab_id then
				if opts.on_error then
					opts.on_error(result, err)
				end
				return
			end

			job.herdr_tab_id = tab_id
			job.herdr_pane_id = pane_id
			run(M.ephemeral_pane_run_args(job), {
				on_success = opts.on_success,
				on_error = function(start_result, message)
					M.close_tab(job)
					if opts.on_error then
						opts.on_error(start_result, message)
					end
				end,
			})
		end,
	})
end

function M.agent_start_args(session)
	return {
		"agent",
		"start",
		session.herdr_agent_name,
		"--kind",
		"codex",
		"--pane",
		session.herdr_pane_id,
		"--timeout",
		"60000",
		"--",
		"--cd",
		session.cwd,
	}
end

function M.create_backing_agent(session, opts)
	opts = opts or {}
	run(M.tab_create_args(session), {
		on_error = opts.on_error,
		on_success = function(result)
			local tab_id, pane_id, err = M.parse_tab_create(result.stdout)
			if not tab_id then
				if opts.on_error then
					opts.on_error(result, err)
				end
				return
			end
			session.herdr_tab_id = tab_id
			session.herdr_pane_id = pane_id
			run(M.agent_start_args(session), {
				on_success = opts.on_success,
				on_error = function(start_result, message)
					M.close_tab(session)
					if opts.on_error then
						opts.on_error(start_result, message)
					end
				end,
			})
		end,
	})
end

function M.attach(session, on_exit)
	local job_id
	local ok = pcall(vim.api.nvim_buf_call, session.bufnr, function()
		job_id = vim.fn.jobstart({ herdr_binary(), "agent", "attach", session.herdr_agent_name }, {
			term = true,
			on_exit = function(exited_job_id, code)
				if on_exit then
					on_exit(exited_job_id, code)
				end
			end,
		})
	end)
	if not ok or not job_id or job_id <= 0 then
		return nil
	end
	return job_id
end

function M.agent_exists(agent_name, callback)
	run({ "agent", "get", agent_name }, {
		on_success = function(result)
			callback(true, result)
		end,
		on_error = function(result)
			callback(false, result)
		end,
	})
end

function M.close_tab(session, opts)
	opts = opts or {}
	if not session or not session.herdr_tab_id then
		if opts.on_success then
			opts.on_success({ code = 0, stdout = "", stderr = "" })
		end
		return
	end
	run({ "tab", "close", session.herdr_tab_id }, opts)
end

function M.rename_tab(session, title)
	if not session or not session.herdr_tab_id or not title or title == "" then
		return
	end
	run({ "tab", "rename", session.herdr_tab_id, title })
end

function M.filter_agents(agents, workspace_id, represented)
	local matches = {}
	represented = represented or {}
	for _, agent in ipairs(agents or {}) do
		local name = agent.name
		if
			name
			and name:sub(1, #AGENT_PREFIX) == AGENT_PREFIX
			and agent.agent == "codex"
			and agent.workspace_id == workspace_id
			and not represented[name]
			and vim.fn.filereadable(M.route_path(name)) == 1
		then
			table.insert(matches, agent)
		end
	end
	table.sort(matches, function(left, right)
		return (left.name or "") < (right.name or "")
	end)
	return matches
end

function M.list_agents(opts)
	opts = opts or {}
	run({ "agent", "list" }, {
		on_error = opts.on_error,
		on_success = function(result)
			local ok, response = pcall(vim.json.decode, result.stdout or "")
			local agents = ok and response and response.result and response.result.agents or nil
			if type(agents) ~= "table" then
				if opts.on_error then
					opts.on_error(result, "invalid Herdr agent list response")
				end
				return
			end
			if opts.on_success then
				opts.on_success(agents)
			end
		end,
	})
end

return M
