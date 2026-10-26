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
		{ text = true, timeout = opts.timeout },
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

-- Keep Git calls asynchronous and tied to the repository where the picker opened.
local function run_git(cwd, args, callback)
	if M._test.git then
		M._test.git(args, cwd, callback)
		return
	end
	vim.system(
		vim.list_extend({ "git" }, args),
		{ cwd = cwd, text = true, env = { GIT_TERMINAL_PROMPT = "0" } },
		vim.schedule_wrap(callback)
	)
end

local function decode_result(result, description)
	local ok, envelope = pcall(vim.json.decode, result.stdout or "", { luanil = { object = true } })
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

local function table_index(items, key)
	local indexed = {}
	for _, item in ipairs(items or {}) do
		if type(item) == "table" and type(item[key]) == "string" then
			indexed[item[key]] = item
		end
	end
	return indexed
end

local function build_agent_items(snapshot)
	local workspaces = table_index(snapshot.workspaces, "workspace_id")
	local tabs = table_index(snapshot.tabs, "tab_id")
	local panes = table_index(snapshot.panes, "pane_id")
	local items = {}
	for index, agent in ipairs(snapshot.agents or {}) do
		if type(agent) == "table" and type(agent.pane_id) == "string" then
			local workspace = workspaces[agent.workspace_id] or {}
			local tab = tabs[agent.tab_id] or {}
			local pane = panes[agent.pane_id] or {}
			local name = agent.name or agent.pane_id
			local title = agent.title or agent.display_agent or name
			local workspace_label = workspace.label or workspace.title or agent.workspace_id or "workspace"
			local tab_label = tab.title or tab.label or agent.tab_id or "tab"
			local cwd = agent.foreground_cwd or agent.cwd or pane.cwd or workspace.cwd or ""
			local status = agent.agent_status or "unknown"
			table.insert(items, {
				idx = index,
				text = table.concat({ status, workspace_label, tab_label, name, title, cwd }, " "),
				name = name,
				title = title,
				status = status,
				workspace_label = workspace_label,
				tab_label = tab_label,
				agent_cwd = cwd,
				agent_pane_id = agent.pane_id,
				agent = agent.agent,
				workspace_id = agent.workspace_id,
				tab_id = agent.tab_id,
				raw_agent = agent,
			})
		end
	end
	return items
end

local STATUS_STYLE = {
	blocked = { "●", "DiagnosticError" },
	done = { "●", "DiagnosticOk" },
	idle = { "○", "DiagnosticHint" },
	working = { "●", "DiagnosticInfo" },
	unknown = { "?", "Comment" },
}

local function format_agent(item)
	local style = STATUS_STYLE[item.status] or STATUS_STYLE.unknown
	local label = item.name
	if item.title ~= item.name then
		label = label .. " — " .. item.title
	end
	return {
		{ style[1] .. " ", style[2] },
		{ string.format("%-8s", item.status), style[2] },
		{ item.workspace_label, "Directory" },
		{ " / ", "Comment" },
		{ item.tab_label, "Title" },
		{ "  " .. label },
		{ item.agent_cwd ~= "" and ("  " .. vim.fn.fnamemodify(item.agent_cwd, ":~")) or "", "Comment" },
	}
end

local function preview_agent(ctx)
	if not ctx.item or not ctx.item.agent_pane_id then
		return
	end
	ctx.preview:reset()
	ctx.preview:minimal()
	ctx.preview:wo({ wrap = false })
	ctx.preview:set_title(ctx.item.workspace_label .. " / " .. ctx.item.tab_label .. " / " .. ctx.item.name)
	require("snacks.picker.preview").cmd({
		vim.fn.stdpath("config") .. "/bin/herdr-pane-preview",
		ctx.item.agent_pane_id,
		tostring(math.max(2, vim.api.nvim_win_get_width(ctx.win))),
	}, ctx, { term = false, ansi = true })
end

local function focus_agent_item(item)
	run({ "agent", "get", item.name or item.agent_pane_id }, {
		timeout = 5000,
		on_success = function(result)
			local payload, err = decode_result(result, "agent")
			local agent = payload and payload.agent
			if type(agent) ~= "table" or not agent.workspace_id or not agent.tab_id or not agent.pane_id then
				fail_step("agent navigation", err or "agent location is unavailable; refresh the picker")
				return
			end
			local steps = {
				{ "workspace", "focus", agent.workspace_id },
				{ "tab", "focus", agent.tab_id },
				{ "agent", "focus", agent.name or agent.pane_id },
				{ "pane", "zoom", agent.pane_id, "--on" },
			}
			local function next_step(index)
				if not steps[index] then
					return
				end
				run(steps[index], {
					timeout = 5000,
					on_success = function()
						next_step(index + 1)
					end,
					on_error = function(_, message)
						fail_step("agent navigation", message)
					end,
				})
			end
			next_step(1)
		end,
		on_error = function(_, message)
			fail_step("agent navigation", message)
		end,
	})
end

M.focus_agent_item = focus_agent_item

function M.agent_snapshot(callback)
	run({ "api", "snapshot" }, {
		timeout = 5000,
		on_error = function(_, message)
			callback(nil, message)
		end,
		on_success = function(result)
			local payload, err = decode_result(result, "snapshot")
			if not payload or type(payload.snapshot) ~= "table" or type(payload.snapshot.agents) ~= "table" then
				callback(nil, err or "invalid Herdr snapshot")
				return
			end
			callback(build_agent_items(payload.snapshot))
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
			fail_step("OpenCode shell readiness", message or "timed out waiting for the root shell")
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
		util.notify("OpenCode job started" .. (label ~= "" and (" in " .. label) or ""))
	end
	local args = {
		"agent",
		"start",
		name,
		"--kind",
		"opencode",
		"--pane",
		pane_id,
		"--timeout",
		"60000",
		"--",
	}
	if opts.resume then
		vim.list_extend(args, { "--continue", cwd })
	else
		table.insert(args, cwd)
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
				fail_step("OpenCode start", message)
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
		util.notify("starting OpenCode in the worktree...")
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
	local args = {
		"worktree",
		"create",
		"--cwd",
		opts.cwd or current_cwd(),
		"--branch",
		branch,
		"--label",
		workspace_label(branch),
		"--no-focus",
	}
	if opts.base then
		vim.list_extend(args, { "--base", opts.base })
	end
	run(args, {
		on_error = function(_, message)
			if opts.tracking_created then
				message = message .. ". Tracking branch '" .. branch .. "' was preserved; retry its [local] row."
			end
			fail_step("worktree creation", message)
		end,
		on_success = function(result)
			local workspace, checkout, already_open, err = parse_workspace_result(result, "worktree creation")
			if not workspace then
				fail_step("worktree creation", err)
				return
			end
			if already_open and opts.focus then
				focus_workspace(workspace.workspace_id)
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
	require("opencode.backend").generate(instruction, current_cwd(), function(code, stdout, stderr)
			if code ~= 0 then
				fail_step("branch-name generation", stderr)
				return
			end
			local branch = util.trim(stdout)
			if branch == "" or branch:find("\n", 1, true) then
				fail_step("branch-name generation", "OpenCode did not return one branch name")
				return
			end
			callback(branch)
		end)
end

local function nonempty_string(value)
	if type(value) == "string" and value:find("%S") then
		return value
	end
	return nil
end

local function list_worktrees(callback, cwd)
	run({ "worktree", "list", "--cwd", cwd or current_cwd() }, {
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
			for _, item in ipairs(items) do
				item.branch = nonempty_string(item.branch)
				item.open_workspace_id = nonempty_string(item.open_workspace_id)
			end
			callback(items, payload.source)
		end,
	})
end

local function list_branches(cwd, callback)
	local function failed(result)
		local message = "Git branch list failed: " .. command_error(result)
		util.notify(message, vim.log.levels.WARN)
		callback({}, message)
	end
	run_git(cwd, { "remote" }, function(remote_result)
		if remote_result.code ~= 0 then
			failed(remote_result)
			return
		end
		local remotes = vim.split(remote_result.stdout or "", "\n", { trimempty = true })
		-- Remote names can contain slashes; remove the longest actual remote prefix.
		table.sort(remotes, function(a, b)
			return #a > #b
		end)
		run_git(cwd, {
			"for-each-ref",
			"--sort=refname",
			"--format=%(refname)%09%(symref)%09%(objectname)%09%(upstream)",
			"refs/heads",
			"refs/remotes",
		}, function(result)
			if result.code ~= 0 then
				failed(result)
				return
			end
			-- %(upstream) can be empty when a configured remote has disappeared.
			run_git(
				cwd,
				{ "config", "--null", "--name-only", "--get-regexp", "^branch[.].*[.](remote|merge)$" },
				function(config)
					if config.code ~= 0 and config.code ~= 1 then
						failed(config)
						return
					end
					local configured = {}
					for _, key in ipairs(vim.split(config.stdout or "", "\0", { plain = true, trimempty = true })) do
						local name = key:match("^branch%.(.*)%.remote$") or key:match("^branch%.(.*)%.merge$")
						if name then
							configured[name] = true
						end
					end
					local branches = {}
					for _, line in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
						local ref, symref, oid, upstream = line:match("^([^\t]+)\t([^\t]*)\t([^\t]+)\t([^\t]*)$")
						if ref and symref == "" then
							if vim.startswith(ref, "refs/heads/") then
								local branch = ref:sub(#"refs/heads/" + 1)
								table.insert(branches, {
									kind = "local",
									branch = branch,
									label = branch,
									ref = ref,
									oid = oid,
									upstream = nonempty_string(upstream),
									has_upstream_config = configured[branch] == true,
								})
							elseif vim.startswith(ref, "refs/remotes/") then
								local label = ref:sub(#"refs/remotes/" + 1)
								for _, remote in ipairs(remotes) do
									if vim.startswith(label, remote .. "/") then
										table.insert(branches, {
											kind = "remote",
											branch = label:sub(#remote + 2),
											label = label,
											ref = ref,
											oid = oid,
										})
										break
									end
								end
							end
						end
					end
					callback(branches)
				end
			)
		end)
	end)
end

-- Upstream identity takes precedence over coincidentally equal branch tips.
local function remote_matches(remote, branches)
	local matches = {}
	local identical
	for _, branch in ipairs(branches) do
		if branch.kind == "local" then
			if branch.upstream == remote.ref then
				table.insert(matches, branch)
			elseif
				branch.branch == remote.branch
				and not branch.upstream
				and not branch.has_upstream_config
				and branch.oid == remote.oid
			then
				identical = branch
			end
		end
	end
	if #matches == 0 and identical then
		table.insert(matches, identical)
	end
	return matches
end

local function local_destination(branch, checkouts)
	local checkout = checkouts[branch.branch]
	if checkout then
		return branch.branch .. (checkout.open_workspace_id and " [open]" or " [checkout]")
	end
	return branch.branch
end

local function worktree_item_label(item, workspaces)
	if item.kind == "fetch" then
		return "Fetch remotes / refresh"
	elseif item.kind == "local" or item.kind == "remote" then
		local label = "[" .. item.kind .. "] " .. item.label
		if item.match_labels and #item.match_labels > 0 then
			label = label .. " → " .. table.concat(item.match_labels, ", ")
		end
		return label
	end
	local workspace = workspaces[item.open_workspace_id] or {}
	local path = nonempty_string(item.path)
	local folder = path and nonempty_string(vim.fn.fnamemodify(path:gsub("/+$", ""), ":t"))
	local label = nonempty_string(workspace.label) or folder or path or nonempty_string(item.label) or "unknown"
	if item.branch and item.branch ~= label then
		label = label .. " (" .. item.branch .. ")"
	end
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
		local has_open_workspace = false
		for _, item in ipairs(items) do
			if
				(not opts.linked_only or item.is_linked_worktree == true)
				and (not opts.open_only or item.open_workspace_id ~= nil)
			then
				table.insert(choices, item)
				has_open_workspace = has_open_workspace or item.open_workspace_id ~= nil
			end
		end
		if #choices == 0 and not opts.branches then
			util.notify(opts.empty_message or "no matching Herdr worktrees", vim.log.levels.WARN)
			return
		end
		local function select(workspaces)
			vim.ui.select(choices, {
				prompt = opts.prompt,
				format_item = function(item)
					return worktree_item_label(item, workspaces)
				end,
			}, function(choice)
				if choice then
					callback(choice)
				end
			end)
		end
		local function show(workspaces)
			if not opts.branches then
				select(workspaces)
				return
			end
			list_branches(opts.cwd, function(branches)
				local checked_out = {}
				for _, item in ipairs(items) do
					if item.branch then
						checked_out[item.branch] = item
					end
				end
				for _, branch in ipairs(branches) do
					if branch.kind == "remote" then
						branch.match_labels = {}
						for _, match in ipairs(remote_matches(branch, branches)) do
							table.insert(branch.match_labels, local_destination(match, checked_out))
						end
					end
					if branch.kind == "remote" or not checked_out[branch.branch] then
						table.insert(choices, branch)
					end
				end
				table.insert(choices, { kind = "fetch" })
				select(workspaces)
			end)
		end
		if not has_open_workspace then
			show({})
			return
		end
		local function fallback(message)
			util.notify("Herdr workspace names unavailable; using folder names: " .. message, vim.log.levels.WARN)
			show({})
		end
		run({ "workspace", "list" }, {
			on_error = function(_, message)
				fallback(message)
			end,
			on_success = function(result)
				local payload, err = decode_result(result, "workspace list")
				local workspaces = payload and payload.workspaces or nil
				if type(workspaces) ~= "table" then
					fallback(err or "response did not include workspaces")
					return
				end
				show(table_index(workspaces, "workspace_id"))
			end,
		})
	end, opts.cwd)
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

local function open_worktree(cwd, item, resume)
	if item.open_workspace_id then
		focus_workspace(item.open_workspace_id)
		return
	end
	run({ "worktree", "open", "--cwd", cwd, "--path", item.path, "--no-focus" }, {
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
			if resume then
				bootstrap_agent_workspace(workspace, checkout or item.path, { resume = true, focus = true })
			else
				bootstrap_editor_workspace(workspace, checkout or item.path)
			end
		end,
	})
end

local function branch_exists(cwd, branch, callback)
	run_git(cwd, { "show-ref", "--verify", "--quiet", "refs/heads/" .. branch }, function(result)
		if result.code == 0 or result.code == 1 then
			callback(result.code == 0)
		else
			fail_step("branch lookup", command_error(result))
		end
	end)
end

local function open_local_branch(cwd, branch, resume, tracking_created)
	branch_exists(cwd, branch, function(exists)
		if not exists then
			util.notify("local branch '" .. branch .. "' no longer exists; refresh the picker", vim.log.levels.WARN)
			return
		end
		list_worktrees(function(items)
			for _, item in ipairs(items) do
				if item.branch == branch then
					open_worktree(cwd, item, resume)
					return
				end
			end
			create_worktree(branch, {
				cwd = cwd,
				base = "refs/heads/" .. branch,
				resume = resume,
				editor = not resume,
				focus = true,
				tracking_created = tracking_created,
			})
		end, cwd)
	end)
end

local function report_branch_status(cwd, branch, remote, callback)
	run_git(cwd, { "rev-list", "--left-right", "--count", branch.ref .. "..." .. remote.ref }, function(result)
		local ahead, behind = (result.stdout or ""):match("^%s*(%d+)%s+(%d+)%s*$")
		if result.code ~= 0 or not ahead then
			local message = result.code ~= 0 and command_error(result) or "invalid ahead/behind counts"
			util.notify("Git branch comparison failed: " .. message, vim.log.levels.WARN)
		else
			ahead, behind = tonumber(ahead), tonumber(behind)
			local status = "equal"
			if ahead > 0 and behind > 0 then
				status = "diverged"
			elseif ahead > 0 then
				status = "ahead"
			elseif behind > 0 then
				status = "behind"
			end
			util.notify(
				string.format("%s vs %s: %s (%d ahead, %d behind)", branch.branch, remote.label, status, ahead, behind)
			)
		end
		callback()
	end)
end

local function selected_remote(branches, ref)
	local remote = table_index(branches, "ref")[ref]
	if not remote or remote.kind ~= "remote" then
		util.notify("selected remote branch no longer exists; refresh the picker", vim.log.levels.ERROR)
		return nil
	end
	return remote
end

local function open_remote_local(cwd, remote_ref, local_ref, resume, reconcile)
	-- A chooser may have been open while refs or upstream configuration changed.
	list_branches(cwd, function(branches, err)
		if err then
			return
		end
		local remote = selected_remote(branches, remote_ref)
		if not remote then
			return
		end
		local branch = table_index(branches, "ref")[local_ref]
		if not branch or branch.kind ~= "local" then
			util.notify("local branch no longer exists; refresh the picker", vim.log.levels.WARN)
			return
		end
		if reconcile then
			local still_matches = false
			for _, match in ipairs(remote_matches(remote, branches)) do
				still_matches = still_matches or match.ref == local_ref
			end
			if not still_matches then
				util.notify("local branch relationship changed; refresh the picker", vim.log.levels.WARN)
				return
			end
		end
		local function open()
			report_branch_status(cwd, branch, remote, function()
				open_local_branch(cwd, branch.branch, resume)
			end)
		end
		if reconcile and not branch.upstream then
			run_git(cwd, { "branch", "--set-upstream-to=" .. remote.ref, "--", branch.branch }, function(result)
				if result.code ~= 0 then
					fail_step("upstream configuration", command_error(result))
					return
				end
				open()
			end)
		else
			open()
		end
	end)
end

local function open_remote_branch(cwd, item, resume)
	local create_tracking
	local function choose_name()
		prompts.input("New local branch tracking " .. item.label .. ": ", function(branch)
			-- Validate the literal name rather than expanding checkout shorthands.
			if branch:sub(1, 1) == "-" then
				util.notify("invalid branch name: " .. branch, vim.log.levels.ERROR)
				return
			end
			run_git(cwd, { "check-ref-format", "refs/heads/" .. branch }, function(result)
				if result.code ~= 0 then
					util.notify("invalid branch name: " .. branch, vim.log.levels.ERROR)
					return
				end
				create_tracking(branch)
			end)
		end)
	end
	local function collision(branch)
		vim.ui.select({
			{ label = "Open existing local branch " .. branch, reuse = true },
			{ label = "Create under another local name" },
		}, {
			prompt = "Local branch '" .. branch .. "' already exists",
			format_item = function(choice)
				return choice.label
			end,
		}, function(choice)
			if not choice then
				return
			end
			if choice.reuse then
				open_remote_local(cwd, item.ref, "refs/heads/" .. branch, resume, false)
			else
				choose_name()
			end
		end)
	end
	create_tracking = function(branch)
		branch_exists(cwd, branch, function(exists)
			if exists then
				collision(branch)
				return
			end
			-- Git creates the branch and its upstream together, and refuses collisions.
			run_git(cwd, { "branch", "--track", "--", branch, item.ref }, function(result)
				if result.code == 0 then
					open_local_branch(cwd, branch, resume, true)
					return
				end
				branch_exists(cwd, branch, function(appeared)
					if appeared then
						util.notify(
							"Git tracking branch creation failed: " .. command_error(result),
							vim.log.levels.WARN
						)
						collision(branch)
					else
						fail_step("tracking branch creation", command_error(result))
					end
				end)
			end)
		end)
	end
	list_branches(cwd, function(branches, err)
		if err then
			return
		end
		local remote = selected_remote(branches, item.ref)
		if not remote then
			return
		end
		item = remote
		local matches = remote_matches(remote, branches)
		if #matches == 0 then
			create_tracking(item.branch)
		elseif #matches == 1 then
			open_remote_local(cwd, remote.ref, matches[1].ref, resume, true)
		else
			list_worktrees(function(checkouts)
				local by_branch = table_index(checkouts, "branch")
				vim.ui.select(matches, {
					prompt = "Local branches matching " .. remote.label,
					format_item = function(branch)
						return local_destination(branch, by_branch)
					end,
				}, function(choice)
					if choice then
						open_remote_local(cwd, remote.ref, choice.ref, resume, true)
					end
				end)
			end, cwd)
		end
	end)
end

local function open_picker(cwd, resume)
	select_worktree({
		prompt = resume and "Continue Herdr worktree" or "Open Herdr worktree",
		cwd = cwd,
		branches = true,
	}, function(item)
		if item.kind == "fetch" then
			util.notify("fetching remotes...")
			run_git(cwd, { "fetch", "--all" }, function(result)
				if result.code ~= 0 then
					util.notify("Git fetch failed: " .. command_error(result), vim.log.levels.WARN)
				end
				open_picker(cwd, resume)
			end)
		elseif item.kind == "remote" then
			open_remote_branch(cwd, item, resume)
		elseif item.kind == "local" then
			open_local_branch(cwd, item.branch, resume)
		else
			list_worktrees(function(items)
				for _, latest in ipairs(items) do
					if latest.path == item.path then
						open_worktree(cwd, latest, resume)
						return
					end
				end
				util.notify("selected checkout no longer exists; refresh the picker", vim.log.levels.WARN)
			end, cwd)
		end
	end)
end

function M.open(resume)
	open_picker(current_cwd(), resume)
end

function M.select_workspace()
	M.agent_snapshot(function(items, err)
		if not items then
			fail_step("agent snapshot", err)
			return
		end
		if #items == 0 then
			util.notify("no Herdr agents found", vim.log.levels.WARN)
			return
		end
		local Snacks = _G.Snacks or require("snacks")
		Snacks.picker.pick({
			title = "Herdr Agents",
			items = items,
			format = format_agent,
			preview = preview_agent,
			confirm = function(picker, item)
				picker:close()
				if item then
					focus_agent_item(item)
				end
			end,
		})
	end)
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
M._test.build_agent_items = build_agent_items
M._test.format_agent = format_agent
M._test.preview_agent = preview_agent
M._test.focus_agent_item = focus_agent_item

return M
