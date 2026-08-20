local util = require("codex.util")

local M = {}
M._test = {}

local AGENT_PREFIX = "nvim-codex-"
local LIFECYCLE_SUBDIR = "libexec/codex-herdr"
local ROUTE_SUBDIR = "codex/herdr"
local SHELL_READY_ATTEMPTS = 40
local SHELL_READY_DELAY_MS = 100

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

function M.codex_workspace_id()
	return vim.env.HERDR_WORKSPACE_ID
end

function M.lifecycle_wrapper_dir()
	return util.join_path(vim.fn.stdpath("config"), LIFECYCLE_SUBDIR)
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
	if M._test.run then
		M._test.run(args, opts)
		return
	end
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
	session.herdr_tab_id = vim.env.HERDR_TAB_ID
	session.herdr_host_pane_id = vim.env.HERDR_PANE_ID
	return M.write_route(session)
end

---Reports which Neovim pane owns a backing Codex agent.
---This metadata is advisory, so reporting failures never interrupt startup.
function M.report_host(session)
	if not session or not session.herdr_pane_id or not session.herdr_host_pane_id then
		return
	end
	run({
		"pane",
		"report-metadata",
		session.herdr_pane_id,
		"--source",
		"nvim:codex-host",
		"--token",
		"nvim_host_pane=" .. session.herdr_host_pane_id,
	})
end

function M.pane_split_args(session)
	local current_path = vim.env.PATH or ""
	local wrapper_dir = session.herdr_wrapper_dir or M.lifecycle_wrapper_dir()
	local wrapped_path = wrapper_dir .. (current_path ~= "" and (":" .. current_path) or "")
	return {
		"pane",
		"split",
		session.herdr_host_pane_id,
		"--direction",
		"right",
		"--ratio",
		"0.4",
		"--cwd",
		session.cwd,
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
		"--focus",
	}
end

function M.parse_pane_split(output)
	local ok, response = pcall(vim.json.decode, output or "")
	if not ok or type(response) ~= "table" or type(response.result) ~= "table" then
		return nil, "invalid Herdr pane response"
	end
	local pane = response.result.pane or response.result.root_pane
	if type(pane) ~= "table" or not pane.pane_id then
		return nil, "Herdr pane response did not include a pane id"
	end
	return pane.pane_id
end

local function shell_is_ready(output)
	local ok, response = pcall(vim.json.decode, output or "")
	local result = ok and type(response) == "table" and response.result or nil
	local info = type(result) == "table" and result.process_info or nil
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

local function wait_for_shell(pane_id, opts, attempt)
	attempt = attempt or 1
	local function retry(result, message)
		if attempt >= SHELL_READY_ATTEMPTS then
			if opts.on_error then
				opts.on_error(result, message or "timed out waiting for the Codex pane shell")
			end
			return
		end
		vim.defer_fn(function()
			wait_for_shell(pane_id, opts, attempt + 1)
		end, SHELL_READY_DELAY_MS)
	end
	run({ "pane", "process-info", "--pane", pane_id }, {
		on_error = retry,
		on_success = function(result)
			if shell_is_ready(result.stdout) then
				opts.on_success(result)
				return
			end
			retry(result)
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

local function start_agent_when_available(session, opts, attempt)
	attempt = attempt or 1
	wait_for_shell(session.herdr_pane_id, {
		on_error = opts.on_error,
		on_success = function()
			run(M.agent_start_args(session), {
				on_success = opts.on_success,
				on_error = function(result, message)
					local pane_busy = tostring(message or ""):find("agent_pane_busy", 1, true) ~= nil
					if not pane_busy or attempt >= SHELL_READY_ATTEMPTS then
						if opts.on_error then
							opts.on_error(result, message)
						end
						return
					end
					vim.defer_fn(function()
						start_agent_when_available(session, opts, attempt + 1)
					end, SHELL_READY_DELAY_MS)
				end,
			})
		end,
	})
end

function M.create_backing_agent(session, opts)
	opts = opts or {}
	run(M.pane_split_args(session), {
		on_error = opts.on_error,
		on_success = function(result)
			local pane_id, err = M.parse_pane_split(result.stdout)
			if not pane_id then
				if opts.on_error then
					opts.on_error(result, err)
				end
				return
			end
			session.herdr_pane_id = pane_id
			M.report_host(session)
			start_agent_when_available(session, {
				on_error = function(start_result, message)
					M.restore_host_view(session, function()
						M.close_pane(session)
						if opts.on_error then
							opts.on_error(start_result, message)
						end
					end)
				end,
				on_success = function(start_result)
					M.restore_host_view(session, function()
						if opts.on_success then
							opts.on_success(start_result)
						end
					end)
				end,
			})
		end,
	})
end

function M.restore_host_view(session, callback)
	local function zoom_host()
		run({ "pane", "zoom", session.herdr_host_pane_id, "--on" }, {
			on_error = function()
				if callback then
					callback()
				end
			end,
			on_success = function()
				if callback then
					callback()
				end
			end,
		})
	end
	run({ "pane", "focus", "--pane", session.herdr_pane_id, "--direction", "left" }, {
		on_error = zoom_host,
		on_success = zoom_host,
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

function M.close_pane(session, opts)
	opts = opts or {}
	if not session or not session.herdr_pane_id then
		if opts.on_success then
			opts.on_success({ code = 0, stdout = "", stderr = "" })
		end
		return
	end
	run({ "pane", "close", session.herdr_pane_id }, opts)
end

function M.rename_tab(session, title)
	if not session or not session.herdr_tab_id or not title or title == "" then
		return
	end
	run({ "tab", "rename", session.herdr_tab_id, title })
end

function M.filter_agents(agents, represented, opts)
	local matches = {}
	represented = represented or {}
	opts = opts or {}
	for _, agent in ipairs(agents or {}) do
		local name = agent.name
		if
			name
			and name:sub(1, #AGENT_PREFIX) == AGENT_PREFIX
			and agent.agent == "codex"
			and not represented[name]
			and (not opts.tab_id or agent.tab_id == opts.tab_id)
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
