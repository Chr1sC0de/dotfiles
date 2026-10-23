vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
package.path = table.concat({
	vim.fn.getcwd() .. "/config/nvim/lua/?.lua",
	vim.fn.getcwd() .. "/config/nvim/lua/?/init.lua",
	package.path,
}, ";")

local actions = require("workmux.actions")
local herdr = require("workmux.herdr")

local function assert_equal(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_command(calls, prefix, label)
	for _, args in ipairs(calls) do
		local matches = true
		for index, value in ipairs(prefix) do
			if args[index] ~= value then
				matches = false
				break
			end
		end
		if matches then
			return args
		end
	end
	error(label .. ": command not found: " .. table.concat(prefix, " "))
end

local function assert_no_command(calls, prefix, label)
	for _, args in ipairs(calls) do
		local matches = true
		for index, value in ipairs(prefix) do
			if args[index] ~= value then
				matches = false
				break
			end
		end
		if matches then
			error(label .. ": unexpected command: " .. table.concat(args, " "))
		end
	end
end

local function response(result)
	return { code = 0, stderr = "", stdout = vim.json.encode({ result = result }) }
end

local function shell_ready_response()
	return response({
		process_info = {
			shell_pid = 42,
			foreground_process_group_id = 42,
			foreground_processes = { { pid = 42, name = "bash" } },
		},
	})
end

local tests = {}

tests["router prefers Herdr and otherwise requires tmux"] = function()
	local old_available = herdr.available
	local old_herdr_env = vim.env.HERDR_ENV
	local old_tmux = vim.env.TMUX
	herdr.available = function()
		return true
	end
	vim.env.HERDR_ENV = "1"
	vim.env.TMUX = "tmux-socket"
	assert_equal(actions._test.active_backend(), "herdr", "Herdr precedence")

	herdr.available = function()
		return false
	end
	vim.env.HERDR_ENV = nil
	assert_equal(actions._test.active_backend(), "workmux", "tmux fallback")
	vim.env.TMUX = nil
	local old_notify = vim.notify
	vim.notify = function() end
	assert_equal(actions._test.active_backend(), nil, "unsupported host")
	vim.notify = old_notify
	vim.env.HERDR_ENV = old_herdr_env
	vim.env.TMUX = old_tmux
	herdr.available = old_available
end

tests["generic commands retain Workmux compatibility aliases"] = function()
	local api = require("workmux")
	api.setup()
	assert_equal(vim.fn.exists(":WorktreeAddPrompt"), 2, "generic add command")
	assert_equal(vim.fn.exists(":WorktreePromptContextToggle"), 2, "generic context command")
	assert_equal(vim.fn.exists(":WorkmuxAddPrompt"), 2, "legacy add command")
	assert_equal(vim.fn.exists(":WorkmuxPromptContextToggle"), 2, "legacy context command")
end

tests["Herdr workspace responses use native checkout metadata"] = function()
	local workspace, path, already_open = herdr._test.parse_workspace_result(
		response({
			workspace = {
				workspace_id = "w9",
				worktree = { checkout_path = "/tmp/repo-feature" },
			},
			already_open = true,
		}),
		"worktree open"
	)
	assert_equal(workspace.workspace_id, "w9", "workspace id")
	assert_equal(path, "/tmp/repo-feature", "checkout path")
	assert_equal(already_open, true, "already open")
	assert_equal(herdr._test.workspace_label("feature/safe name"), "feature-safe-name", "workspace label")
	assert_equal(#herdr._test.agent_name("/tmp/repo-feature") <= 32, true, "bounded agent name")
end

tests["branch creation starts Neovim in the root pane without Codex"] = function()
	local calls = {}
	local process_info_calls = 0
	herdr._test.validate_branch = function(branch, callback)
		callback(branch)
	end
	herdr._test.run = function(args, opts)
		table.insert(calls, vim.deepcopy(args))
		local command = args[1] .. " " .. args[2]
		if command == "worktree create" then
			opts.on_success(response({
				workspace = {
					workspace_id = "w9",
					cwd = "/tmp/repo-feature",
					worktree = { checkout_path = "/tmp/repo-feature" },
				},
			}))
		elseif command == "pane list" then
			opts.on_success(response({ panes = { { pane_id = "w9:p1" } } }))
		elseif command == "pane process-info" then
			process_info_calls = process_info_calls + 1
			if process_info_calls == 1 then
				opts.on_success(response({
					process_info = {
						shell_pid = 42,
						foreground_process_group_id = 99,
						foreground_processes = { { pid = 99, name = "startup" } },
					},
				}))
			else
				opts.on_success(shell_ready_response())
			end
		elseif opts.on_success then
			opts.on_success(response({}))
		end
	end

	herdr.add_branch("feature-safe")
	assert_equal(
		vim.wait(1000, function()
			for _, args in ipairs(calls) do
				if args[1] == "pane" and args[2] == "run" then
					return true
				end
			end
			return false
		end),
		true,
		"Neovim starts after shell readiness"
	)
	assert_command(calls, { "worktree", "create", "--cwd" }, "create worktree")
	assert_no_command(calls, { "pane", "split" }, "single-pane workspace")
	assert_command(calls, { "pane", "process-info", "--pane", "w9:p1" }, "wait for root shell")
	assert_equal(process_info_calls, 2, "shell readiness polls")
	assert_command(calls, { "pane", "run", "w9:p1", "nvim ." }, "start Neovim in root pane")
	assert_no_command(calls, { "agent", "start" }, "branch creation does not start Codex")
	assert_no_command(calls, { "agent", "prompt" }, "branch creation does not prompt Codex")
	assert_command(calls, { "workspace", "focus", "w9" }, "focus editor workspace")

	herdr._test.run = nil
	herdr._test.validate_branch = nil
end

tests["prompt creation generates a branch and submits the task"] = function()
	local calls = {}
	local already_open = false
	local notifications = {}
	local old_notify = vim.notify
	vim.notify = function(message)
		table.insert(notifications, message)
	end
	herdr._test.generate_branch = function(task, callback)
		assert_equal(task, "implement routed workflow", "branch task")
		callback("routed-workflow")
	end
	herdr._test.validate_branch = function(branch, callback)
		callback(branch)
	end
	herdr._test.run = function(args, opts)
		table.insert(calls, vim.deepcopy(args))
		local command = args[1] .. " " .. args[2]
		if command == "worktree create" then
			opts.on_success(response({
				already_open = already_open,
				workspace = {
					workspace_id = "wP",
					cwd = "/tmp/routed-workflow",
					worktree = { checkout_path = "/tmp/routed-workflow" },
				},
			}))
		elseif command == "pane list" then
			opts.on_success(response({ panes = { { pane_id = "wP:p1" } } }))
		elseif command == "pane process-info" then
			opts.on_success(shell_ready_response())
		elseif opts.on_success then
			opts.on_success(response({}))
		end
	end

	herdr.add_prompt("implement routed workflow")
	local create = assert_command(calls, { "worktree", "create" }, "generated worktree")
	assert_equal(vim.tbl_contains(create, "routed-workflow"), true, "generated branch")
	local prompt = assert_command(calls, { "agent", "prompt" }, "initial agent prompt")
	assert_equal(prompt[4], "implement routed workflow", "submitted task")
	assert_no_command(calls, { "pane", "split" }, "prompt workspace remains single-pane")
	assert_no_command(calls, { "pane", "run" }, "prompt workflow does not start Neovim")
	assert_no_command(calls, { "agent", "focus" }, "background prompt preserves focus")
	assert_equal(notifications[#notifications], "worktree: Codex job started in routed-workflow", "started notice")

	already_open, calls = true, {}
	herdr.add_prompt("implement routed workflow")
	assert_command(calls, { "agent", "prompt" }, "background prompt workflow still submits its task")

	vim.notify = old_notify
	herdr._test.generate_branch = nil
	herdr._test.validate_branch = nil
	herdr._test.run = nil
end

tests["prompt creation retries while the root pane becomes available"] = function()
	local agent_attempts = 0
	local process_info_calls = 0
	local prompt_calls = 0
	local notifications = {}
	local old_notify = vim.notify
	local old_defer_fn = vim.defer_fn
	vim.notify = function(message)
		table.insert(notifications, message)
	end
	vim.defer_fn = function(callback)
		callback()
	end
	herdr._test.generate_branch = function(_, callback)
		callback("retry-agent-start")
	end
	herdr._test.validate_branch = function(branch, callback)
		callback(branch)
	end
	herdr._test.run = function(args, opts)
		local command = args[1] .. " " .. args[2]
		if command == "worktree create" then
			opts.on_success(response({
				workspace = {
					workspace_id = "wR",
					cwd = "/tmp/retry-agent-start",
					worktree = { checkout_path = "/tmp/retry-agent-start" },
				},
			}))
		elseif command == "pane list" then
			opts.on_success(response({ panes = { { pane_id = "wR:p1" } } }))
		elseif command == "pane process-info" then
			process_info_calls = process_info_calls + 1
			opts.on_success(shell_ready_response())
		elseif command == "agent start" then
			agent_attempts = agent_attempts + 1
			if agent_attempts < 3 then
				opts.on_error(
					{ code = 1, stderr = '{"error":{"code":"agent_pane_busy"}}', stdout = "" },
					'{"error":{"code":"agent_pane_busy"}}'
				)
			else
				opts.on_success(response({}))
			end
		elseif command == "agent prompt" then
			prompt_calls = prompt_calls + 1
			opts.on_success(response({}))
		end
	end

	herdr.add_prompt("retry transient pane race")
	assert_equal(agent_attempts, 3, "agent start attempts")
	assert_equal(process_info_calls, 3, "shell readiness checks")
	assert_equal(prompt_calls, 1, "initial prompt count")
	assert_equal(notifications[#notifications], "worktree: Codex job started in retry-agent-start", "started notice")

	vim.notify = old_notify
	vim.defer_fn = old_defer_fn
	herdr._test.generate_branch = nil
	herdr._test.validate_branch = nil
	herdr._test.run = nil
end

tests["prompt creation does not retry non-busy agent errors"] = function()
	local agent_attempts = 0
	local notifications = {}
	local old_notify = vim.notify
	vim.notify = function(message)
		table.insert(notifications, message)
	end
	herdr._test.generate_branch = function(_, callback)
		callback("failed-agent-start")
	end
	herdr._test.validate_branch = function(branch, callback)
		callback(branch)
	end
	herdr._test.run = function(args, opts)
		local command = args[1] .. " " .. args[2]
		if command == "worktree create" then
			opts.on_success(response({ workspace = { workspace_id = "wE", cwd = "/tmp/failed-agent-start" } }))
		elseif command == "pane list" then
			opts.on_success(response({ panes = { { pane_id = "wE:p1" } } }))
		elseif command == "pane process-info" then
			opts.on_success(shell_ready_response())
		elseif command == "agent start" then
			agent_attempts = agent_attempts + 1
			opts.on_error({ code = 1, stderr = "agent executable missing", stdout = "" }, "agent executable missing")
		end
	end

	herdr.add_prompt("fail without retry")
	assert_equal(agent_attempts, 1, "agent start attempts")
	assert_equal(
		notifications[#notifications],
		"worktree: Herdr Codex start failed: agent executable missing",
		"failure notice"
	)

	vim.notify = old_notify
	herdr._test.generate_branch = nil
	herdr._test.validate_branch = nil
	herdr._test.run = nil
end

tests["pane discovery failure preserves the created workspace"] = function()
	local calls = {}
	local old_notify = vim.notify
	vim.notify = function() end
	herdr._test.validate_branch = function(branch, callback)
		callback(branch)
	end
	herdr._test.run = function(args, opts)
		table.insert(calls, vim.deepcopy(args))
		local command = args[1] .. " " .. args[2]
		if command == "worktree create" then
			opts.on_success(response({ workspace = { workspace_id = "wF", cwd = "/tmp/failure" } }))
		elseif command == "pane list" then
			opts.on_error({ code = 1, stdout = "", stderr = "pane list failed" }, "pane list failed")
		elseif opts.on_success then
			opts.on_success(response({}))
		end
	end

	herdr.add_branch("preserve-failure")
	for _, args in ipairs(calls) do
		assert_equal(args[1] == "workspace" and args[2] == "close", false, "workspace remains open")
		assert_equal(args[1] == "worktree" and args[2] == "remove", false, "worktree remains")
	end

	vim.notify = old_notify
	herdr._test.validate_branch = nil
	herdr._test.run = nil
end

tests["continue opens a closed checkout with codex resume last"] = function()
	local calls = {}
	local old_select = vim.ui.select
	vim.ui.select = function(items, _, callback)
		callback(items[1])
	end
	herdr._test.run = function(args, opts)
		table.insert(calls, vim.deepcopy(args))
		local command = args[1] .. " " .. args[2]
		if command == "worktree list" then
			opts.on_success(response({
				worktrees = {
					{
						branch = "feature",
						path = "/tmp/repo-feature",
						is_linked_worktree = true,
						open_workspace_id = vim.NIL,
					},
				},
			}))
		elseif command == "worktree open" then
			opts.on_success(response({
				workspace = {
					workspace_id = "wA",
					cwd = "/tmp/repo-feature",
					worktree = { checkout_path = "/tmp/repo-feature" },
				},
				already_open = false,
			}))
		elseif command == "pane list" then
			opts.on_success(response({ panes = { { pane_id = "wA:p1" } } }))
		elseif command == "pane process-info" then
			opts.on_success(shell_ready_response())
		elseif opts.on_success then
			opts.on_success(response({}))
		end
	end

	herdr.open(true)
	local start = assert_command(calls, { "agent", "start" }, "resume Codex")
	local resume_index = vim.fn.index(start, "resume")
	assert_equal(resume_index >= 0, true, "resume argument")
	assert_equal(start[resume_index + 2], "--last", "resume last argument")
	assert_equal(vim.tbl_contains(start, "wA:p1"), true, "resumed Codex uses root pane")
	assert_no_command(calls, { "pane", "split" }, "continued workspace remains single-pane")
	assert_no_command(calls, { "pane", "run" }, "continue workflow does not start Neovim")
	assert_command(calls, { "agent", "focus" }, "explicit continue focuses Codex")

	vim.ui.select = old_select
	herdr._test.run = nil
end

local function with_worktree_picker(worktrees, workspaces, check)
	local calls, notices = {}, {}
	local old_select, old_input, old_notify = vim.ui.select, vim.ui.input, vim.notify
	local old_cwd, old_git = vim.fn.getcwd(), herdr._test.git
	local prompts = require("workmux.prompts")
	local old_confirm = prompts.confirm_exact
	local fixture = {
		workspaces = workspaces,
		worktrees = worktrees,
		git_calls = {},
		menus = {},
		refs = "",
		remotes = "origin\nupstream\n",
		locals = {},
		oids = {},
		configured = {},
	}
	vim.notify = function(message, level)
		table.insert(notices, { message = message, level = level })
	end
	vim.ui.select = function(items, opts, callback)
		local rows = {}
		for _, item in ipairs(items) do
			table.insert(rows, opts.format_item(item))
		end
		fixture.items, fixture.rows = items, rows
		table.insert(fixture.menus, { prompt = opts.prompt, rows = rows })
		local selection = fixture.select
		if fixture.choose then
			selection = fixture.choose(items, opts)
		end
		if type(selection) == "string" then
			selection = vim.fn.index(rows, selection) + 1
			assert_equal(selection > 0, true, "selected row exists")
		end
		callback(selection and items[selection] or nil)
	end
	vim.ui.input = function(_, callback)
		callback(fixture.input)
	end
	prompts.confirm_exact = function(expected, _, callback)
		fixture.confirmed = expected
		callback()
	end
	herdr._test.git = function(args, cwd, callback)
		table.insert(fixture.git_calls, { args = vim.deepcopy(args), cwd = cwd })
		local result = { code = 0, stdout = "", stderr = "" }
		if args[1] == "remote" then
			result.stdout = fixture.remotes
			result.code = fixture.remote_error and 1 or 0
		elseif args[1] == "for-each-ref" then
			local rows, seen = {}, {}
			for _, line in ipairs(vim.split(fixture.refs, "\n", { trimempty = true })) do
				local fields = vim.split(line, "\t", { plain = true })
				if vim.startswith(fields[1], "refs/heads/") then
					local branch = fields[1]:sub(#"refs/heads/" + 1)
					seen[branch] = true
					fields[3] = fixture.oids[branch] or fields[3]
					local upstream = fixture.locals[branch]
					if upstream and vim.startswith(upstream, "refs/remotes/") then
						fields[4] = upstream
					end
				end
				table.insert(rows, table.concat(fields, "\t"))
			end
			local names = vim.tbl_keys(fixture.locals)
			table.sort(names)
			for _, branch in ipairs(names) do
				if not seen[branch] then
					local upstream = fixture.locals[branch]
					table.insert(
						rows,
						table.concat({
							"refs/heads/" .. branch,
							"",
							fixture.oids[branch] or "local-tip",
							vim.startswith(upstream, "refs/remotes/") and upstream or "",
						}, "\t")
					)
				end
			end
			result.stdout = table.concat(rows, "\n")
			result.code = fixture.refs_error and 1 or 0
		elseif args[1] == "config" then
			local keys = {}
			for name in pairs(fixture.configured) do
				table.insert(keys, "branch." .. name .. ".remote")
			end
			result.stdout = table.concat(keys, "\0")
			result.code = fixture.config_error and 3 or (#keys > 0 and 0 or 1)
		elseif args[1] == "show-ref" then
			result.code = fixture.locals[args[4]:sub(#"refs/heads/" + 1)] and 0 or 1
		elseif args[1] == "rev-list" then
			result.stdout = fixture.status_output or "0\t0\n"
			result.code = fixture.status_code or 0
			result.stderr = "comparison unavailable"
		elseif args[1] == "branch" then
			if vim.startswith(args[2], "--set-upstream-to=") then
				if fixture.tracking_error then
					result.code, result.stderr = 1, "cannot write branch configuration"
				else
					fixture.locals[args[4]] = args[2]:sub(#"--set-upstream-to=" + 1)
				end
			elseif fixture.branch_race then
				fixture.locals[args[4]] = "concurrent branch"
				fixture.branch_race = nil
				result.code = 128
			elseif fixture.branch_error then
				result.code, result.stderr = 128, "remote ref is gone"
			else
				fixture.locals[args[4]] = args[5]
				fixture.oids[args[4]] = "remote-tip"
			end
		elseif args[1] == "check-ref-format" then
			result.code = fixture.invalid_branch and 1 or 0
		elseif args[1] == "fetch" then
			if fixture.on_fetch then
				fixture.on_fetch()
			end
			result.code, result.stderr = fixture.fetch_code or 0, "offline"
		else
			error("unexpected Git command: " .. vim.inspect(args))
		end
		callback(result)
	end
	herdr._test.run = function(args, opts)
		table.insert(calls, vim.deepcopy(args))
		local command = args[1] .. " " .. args[2]
		if command == "worktree list" then
			opts.on_success(response({ worktrees = fixture.worktrees }))
		elseif command == "workspace list" then
			if fixture.lookup_error then
				opts.on_error({ code = 1 }, fixture.lookup_error)
			elseif fixture.lookup_response then
				opts.on_success(fixture.lookup_response)
			else
				opts.on_success(response({ workspaces = fixture.workspaces }))
			end
		elseif command == "worktree create" or command == "worktree open" then
			if fixture.create_error then
				opts.on_error({ code = 1 }, "checkout creation refused")
			else
				local payload = {
					workspace = { workspace_id = "wNew", cwd = "/tmp/new-checkout" },
					already_open = fixture.already_open or false,
				}
				if fixture.on_create then
					payload = fixture.on_create(args)
				end
				opts.on_success(response(payload))
			end
		elseif command == "pane list" then
			opts.on_success(response({ panes = { { pane_id = "wNew:p1" } } }))
		elseif command == "pane process-info" then
			opts.on_success(shell_ready_response())
		elseif opts.on_success then
			opts.on_success(response({}))
		end
	end
	local ok, err = xpcall(function()
		check(fixture, calls, notices)
	end, debug.traceback)
	vim.ui.select, vim.ui.input, vim.notify = old_select, old_input, old_notify
	prompts.confirm_exact = old_confirm
	herdr._test.run, herdr._test.git = nil, old_git
	vim.api.nvim_set_current_dir(old_cwd)
	if not ok then
		error(err)
	end
end

tests["worktree picker resolves current workspace names and preserves focus targets"] = function()
	with_worktree_picker({
		{
			label = "feature/login",
			branch = "feature/login",
			path = "/tmp/login-checkout",
			is_linked_worktree = true,
			open_workspace_id = "w7",
		},
		{
			label = "main",
			branch = "main",
			path = "/tmp/project",
			is_linked_worktree = false,
			open_workspace_id = "w1",
		},
	}, {
		{ workspace_id = "w1", label = "Project" },
		{ workspace_id = "w7", label = "Login redesign" },
	}, function(fixture, calls)
		herdr.open(false)
		assert_equal(fixture.rows, {
			"Login redesign (feature/login) [open]",
			"Project (main) [main, open]",
			"Fetch remotes / refresh",
		}, "workspace labels joined by ID")
		assert_equal(#calls, 2, "one workspace lookup and no action after cancellation")
		fixture.workspaces[2].label = "Renamed login"
		fixture.select = 1
		herdr.open(true)
		assert_equal(fixture.rows[1], "Renamed login (feature/login) [open]", "fresh workspace name")
		assert_equal(#calls, 6, "fresh worktree lookup before focus")
		assert_command(calls, { "workspace", "focus", "w7" }, "original workspace target")
		assert_no_command(calls, { "worktree", "open" }, "open workspace is reused")
		assert_equal(fixture.items[1].label, "feature/login", "original worktree label retained")
	end)
end

tests["closed worktree picker uses folder names and handles detached checkouts"] = function()
	with_worktree_picker({
		{
			label = "feature/login",
			branch = "feature/login",
			path = "/tmp/login-checkout/",
			is_linked_worktree = true,
			open_workspace_id = vim.NIL,
		},
		{ label = "release", branch = "release", path = "/tmp/release", is_linked_worktree = true },
		{
			label = "detached HEAD",
			branch = vim.NIL,
			path = "/tmp/detached",
			is_linked_worktree = true,
			open_workspace_id = vim.NIL,
		},
	}, {}, function(fixture, calls)
		herdr.open(false)
		assert_equal(fixture.rows, {
			"login-checkout (feature/login) [closed]",
			"release [closed]",
			"detached [closed]",
			"Fetch remotes / refresh",
		}, "closed and detached labels")
		assert_no_command(calls, { "workspace", "list" }, "closed checkouts need no workspace lookup")
	end)
end

tests["worktree picker falls back when workspace records are absent or lookup fails"] = function()
	with_worktree_picker({
		{
			label = "feature/login",
			branch = "feature/login",
			path = "/tmp/login-checkout",
			is_linked_worktree = true,
			open_workspace_id = "w7",
		},
		{
			label = "release",
			branch = "release",
			path = "/tmp/release",
			is_linked_worktree = true,
			open_workspace_id = "w8",
		},
	}, { { workspace_id = "w8", label = "" } }, function(fixture, _, notices)
		local expected = { "login-checkout (feature/login) [open]", "release [open]", "Fetch remotes / refresh" }
		herdr.open(false)
		assert_equal(fixture.rows, expected, "missing and empty workspace labels")
		assert_equal(#notices, 0, "missing records need no warning")
		fixture.lookup_error = "socket unavailable"
		herdr.open(false)
		assert_equal(fixture.rows, expected, "failed lookup fallback")
		assert_equal(#notices, 1, "single lookup warning")
		assert_equal(notices[1].level, vim.log.levels.WARN, "warning severity")
		fixture.lookup_error = nil
		fixture.lookup_response = response({})
		herdr.open(false)
		assert_equal(fixture.rows, expected, "malformed lookup fallback")
		assert_equal(#notices, 2, "single malformed response warning")
	end)
end

tests["close and remove selectors retain filters and confirmation identity"] = function()
	with_worktree_picker({
		{ branch = "main", path = "/tmp/project", is_linked_worktree = false, open_workspace_id = "w1" },
		{ branch = "closed", path = "/tmp/closed", is_linked_worktree = true, open_workspace_id = vim.NIL },
		{
			label = "feature/login",
			branch = "feature/login",
			path = "/tmp/login-checkout",
			is_linked_worktree = true,
			open_workspace_id = "w7",
		},
	}, { { workspace_id = "w7", label = "Login redesign" } }, function(fixture, calls)
		fixture.select = 1
		herdr.close()
		assert_equal(fixture.rows, { "Login redesign (feature/login) [open]" }, "close selector")
		assert_command(calls, { "workspace", "close", "w7" }, "close target")
		herdr.remove()
		assert_equal(fixture.rows, { "Login redesign (feature/login) [open]" }, "remove selector")
		assert_equal(fixture.confirmed, "feature/login", "existing branch confirmation")
		assert_command(calls, { "worktree", "remove", "--workspace", "w7" }, "remove target")
	end)
end

local function ref_row(ref, target, oid, upstream)
	oid = oid or (vim.startswith(ref, "refs/heads/") and "local-tip" or "remote-tip")
	return table.concat({ ref, target or "", oid, upstream or "" }, "\t") .. "\n"
end

local function remote_choice(items)
	for index, item in ipairs(items) do
		if item.kind == "remote" and item.ref == "refs/remotes/origin/feature/foo" then
			return index
		end
	end
	error("remote row not found")
end

local function remote_fixture(fixture)
	fixture.refs = ref_row("refs/remotes/origin/feature/foo")
	fixture.select = 1
end

local function git_commands(fixture)
	return vim.tbl_map(function(call)
		return call.args
	end, fixture.git_calls)
end

tests["combined picker preserves worktrees and distinct local and remote branches"] = function()
	with_worktree_picker({
		{ branch = "main", path = "/tmp/main", is_linked_worktree = false },
	}, {}, function(fixture, calls)
		fixture.remotes = "origin\nupstream\norigin/team\n"
		fixture.refs = ref_row("refs/heads/main")
			.. ref_row("refs/heads/feature/local")
			.. ref_row("refs/remotes/origin/HEAD", "refs/remotes/origin/main")
			.. ref_row("refs/remotes/origin/feature/foo")
			.. ref_row("refs/remotes/origin/team/feature/foo")
			.. ref_row("refs/remotes/upstream/feature/foo")
		herdr.open(false)
		assert_equal(fixture.rows, {
			"main [main, closed]",
			"[local] feature/local",
			"[remote] origin/feature/foo",
			"[remote] origin/team/feature/foo",
			"[remote] upstream/feature/foo",
			"Fetch remotes / refresh",
		}, "combined rows")
		assert_equal(fixture.items[4].branch, "feature/foo", "actual remote prefix removed")
		assert_no_command(git_commands(fixture), { "fetch" }, "no automatic fetch")
		assert_no_command(git_commands(fixture), { "branch" }, "cancel does not create branches")
		assert_equal(#calls, 1, "cancel does not open workspace")
	end)
end

tests["remote branches create tracking before opening Neovim"] = function()
	with_worktree_picker({}, {}, function(fixture, calls)
		remote_fixture(fixture)
		herdr.open(false)
		assert_command(git_commands(fixture), {
			"branch",
			"--track",
			"--",
			"feature/foo",
			"refs/remotes/origin/feature/foo",
		}, "exact remote tracking")
		assert_equal(fixture.locals["feature/foo"], "refs/remotes/origin/feature/foo", "tracking branch")
		local create = assert_command(calls, { "worktree", "create" }, "create checkout")
		assert_equal(create[vim.fn.index(create, "--base") + 2], "refs/heads/feature/foo", "explicit local base")
		assert_command(calls, { "pane", "run", "wNew:p1", "nvim ." }, "open Neovim")
		assert_command(calls, { "workspace", "focus", "wNew" }, "focus editor workspace")
		assert_no_command(calls, { "agent", "start" }, "normal opening does not start Codex")
		assert_no_command(calls, { "agent", "prompt" }, "normal opening does not submit a task")
	end)
end

tests["remote branches preserve continue behavior"] = function()
	with_worktree_picker({}, {}, function(fixture, calls)
		remote_fixture(fixture)
		herdr.open(true)
		local start = assert_command(calls, { "agent", "start" }, "continued agent")
		assert_equal(vim.tbl_contains(start, "resume"), true, "resume requested")
		assert_equal(vim.tbl_contains(start, "--last"), true, "resume last")
	end)
end

tests["unrepresented local branches create checkouts without changing upstream"] = function()
	with_worktree_picker({}, {}, function(fixture, calls)
		fixture.refs = ref_row("refs/heads/feature/local")
		fixture.locals["feature/local"] = "refs/remotes/upstream/original"
		fixture.select = 1
		herdr.open(false)
		assert_command(calls, { "worktree", "create" }, "local checkout")
		assert_command(calls, { "pane", "run", "wNew:p1", "nvim ." }, "local checkout opens Neovim")
		assert_no_command(calls, { "agent", "start" }, "local opening does not start Codex")
		assert_no_command(git_commands(fixture), { "branch" }, "no branch rewrite")
		assert_equal(fixture.locals["feature/local"], "refs/remotes/upstream/original", "upstream preserved")
	end)
end

tests["remote name collisions offer reuse without changing existing upstream"] = function()
	with_worktree_picker({
		{ branch = "feature/foo", path = "/tmp/foo", open_workspace_id = "wFoo", is_linked_worktree = true },
	}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.locals["feature/foo"] = "refs/remotes/upstream/other"
		fixture.choose = function(_, opts)
			if opts.prompt:find("already exists", 1, true) then
				return 1
			end
			return "[remote] origin/feature/foo"
		end
		herdr.open(false)
		assert_equal(fixture.rows, {
			"Open existing local branch feature/foo",
			"Create under another local name",
		}, "collision choices")
		assert_command(calls, { "workspace", "focus", "wFoo" }, "existing workspace reused")
		assert_no_command(calls, { "worktree", "create" }, "no duplicate checkout")
		assert_no_command(git_commands(fixture), { "branch" }, "existing upstream preserved")
	end)
end

tests["collision alternatives track the originally selected remote"] = function()
	with_worktree_picker({}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.locals["feature/foo"] = "existing"
		fixture.input = "review/foo"
		fixture.choose = function(_, opts)
			return opts.prompt:find("already exists", 1, true) and 2 or 1
		end
		herdr.open(false)
		assert_command(git_commands(fixture), {
			"branch",
			"--track",
			"--",
			"review/foo",
			"refs/remotes/origin/feature/foo",
		}, "renamed branch tracks original ref")
		assert_equal(fixture.locals["feature/foo"], "existing", "original branch preserved")
		assert_command(calls, { "worktree", "create" }, "renamed checkout")
	end)
end

tests["collision cancellation and invalid alternative names do not create branches"] = function()
	for _, input in ipairs({ "bad name", "-option", "@{-1}", "" }) do
		with_worktree_picker({}, {}, function(fixture, calls)
			remote_fixture(fixture)
			fixture.locals["feature/foo"] = "existing"
			fixture.input, fixture.invalid_branch = input, true
			fixture.choose = function(_, opts)
				return opts.prompt:find("already exists", 1, true) and 2 or 1
			end
			herdr.open(false)
			assert_no_command(git_commands(fixture), { "branch" }, "invalid name does not create")
			assert_no_command(calls, { "worktree", "create" }, "invalid name does not open")
		end)
	end
	with_worktree_picker({}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.locals["feature/foo"] = "existing"
		fixture.choose = function(_, opts)
			if not opts.prompt:find("already exists", 1, true) then
				return 1
			end
		end
		herdr.open(false)
		assert_no_command(git_commands(fixture), { "branch" }, "cancel collision")
		assert_no_command(calls, { "worktree", "create" }, "cancel checkout")
	end)
end

tests["branches appearing during creation return to collision choices"] = function()
	with_worktree_picker({}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.branch_race = true
		fixture.choose = function(_, opts)
			if not opts.prompt:find("already exists", 1, true) then
				return 1
			end
		end
		herdr.open(false)
		assert_equal(fixture.locals["feature/foo"], "concurrent branch", "concurrent branch not replaced")
		assert_equal(#fixture.menus, 2, "collision prompt shown")
		assert_no_command(calls, { "worktree", "create" }, "no checkout after cancelled collision")
	end)
end

tests["tracking and checkout failures preserve recoverable state"] = function()
	with_worktree_picker({}, {}, function(fixture, calls, notices)
		remote_fixture(fixture)
		fixture.branch_error = true
		herdr.open(false)
		assert_no_command(calls, { "worktree", "create" }, "no checkout after missing remote")
		assert_equal(notices[#notices].message:find("remote ref is gone", 1, true) ~= nil, true, "tracking failure")
	end)
	with_worktree_picker({}, {}, function(fixture, calls, notices)
		remote_fixture(fixture)
		fixture.create_error = true
		herdr.open(false)
		assert_equal(fixture.locals["feature/foo"], "refs/remotes/origin/feature/foo", "tracking branch retained")
		assert_equal(notices[#notices].message:find("was preserved", 1, true) ~= nil, true, "recovery notice")
		assert_no_command(calls, { "agent", "start" }, "failed checkout does not start agent")
		assert_no_command(git_commands(fixture), { "branch", "-D" }, "no branch rollback")
	end)
end

tests["fetch action reloads available refs even after partial failure"] = function()
	for _, code in ipairs({ 0, 1 }) do
		with_worktree_picker({}, {}, function(fixture, calls, notices)
			fixture.fetch_code = code
			fixture.choose = function()
				if #fixture.menus == 1 then
					return "Fetch remotes / refresh"
				end
			end
			fixture.on_fetch = function()
				fixture.refs = ref_row("refs/remotes/upstream/newly-pushed")
			end
			herdr.open(false)
			assert_command(git_commands(fixture), { "fetch", "--all" }, "explicit fetch")
			assert_equal(fixture.rows, {
				"[remote] upstream/newly-pushed",
				"Fetch remotes / refresh",
			}, "refs reloaded")
			assert_equal(#fixture.menus, 2, "picker reopened")
			assert_equal(#notices, code == 0 and 1 or 2, "fetch failure warning")
			assert_no_command(calls, { "worktree", "create" }, "refresh does not create checkout")
		end)
	end
end

tests["branch listing failure leaves existing worktrees usable"] = function()
	with_worktree_picker({
		{ branch = "main", path = "/tmp/main", open_workspace_id = "wMain", is_linked_worktree = false },
	}, {}, function(fixture, calls, notices)
		fixture.refs_error, fixture.select = true, 1
		herdr.open(false)
		assert_equal(fixture.rows, { "main [main, open]", "Fetch remotes / refresh" }, "fallback rows")
		assert_equal(notices[1].level, vim.log.levels.WARN, "branch warning")
		assert_command(calls, { "workspace", "focus", "wMain" }, "existing workspace usable")
	end)
end

tests["closed checkouts reopen in Neovim unless a workspace is already open"] = function()
	for _, already_open in ipairs({ false, true }) do
		with_worktree_picker({
			{ branch = "feature", path = "/tmp/feature", is_linked_worktree = true },
		}, {}, function(fixture, calls)
			fixture.select, fixture.already_open = 1, already_open
			herdr.open(false)
			assert_command(calls, { "worktree", "open" }, "reopen checkout")
			assert_command(calls, { "workspace", "focus", "wNew" }, "focus workspace")
			assert_no_command(calls, { "agent", "start" }, "normal reopen does not start Codex")
			if already_open then
				assert_no_command(calls, { "pane", "run" }, "already open workspace gets no new Neovim")
			else
				assert_command(calls, { "pane", "run", "wNew:p1", "nvim ." }, "reopened checkout starts Neovim")
			end
		end)
	end
end

tests["remote match to a closed checkout opens Neovim without recreating it"] = function()
	with_worktree_picker({
		{ branch = "review/foo", path = "/tmp/review", is_linked_worktree = true },
	}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.locals["review/foo"] = "refs/remotes/origin/feature/foo"
		fixture.choose = remote_choice
		herdr.open(false)
		assert_command(calls, { "worktree", "open" }, "matched checkout reopened")
		assert_command(calls, { "pane", "run", "wNew:p1", "nvim ." }, "matched checkout opens editor")
		assert_no_command(calls, { "worktree", "create" }, "existing checkout retained")
		assert_no_command(calls, { "agent", "start" }, "matching does not start Codex")
	end)
end

tests["checkout selection rechecks state and never bootstraps an already open workspace"] = function()
	with_worktree_picker({
		{ branch = "feature", path = "/tmp/feature", is_linked_worktree = true },
	}, {}, function(fixture, calls)
		fixture.choose = function()
			fixture.worktrees[1].open_workspace_id = "wConcurrent"
			return 1
		end
		herdr.open(false)
		assert_command(calls, { "workspace", "focus", "wConcurrent" }, "latest workspace state")
		assert_no_command(calls, { "worktree", "open" }, "no duplicate workspace")
		assert_no_command(calls, { "pane", "run" }, "focusing a workspace does not start Neovim")
	end)
	with_worktree_picker({}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.already_open = true
		herdr.open(false)
		assert_command(calls, { "workspace", "focus", "wNew" }, "server reports existing workspace")
		assert_no_command(calls, { "agent", "start" }, "no duplicate agent")
		assert_no_command(calls, { "pane", "run" }, "existing workspace gets no duplicate Neovim")
	end)
end

tests["removed branches and checkouts do not create replacements"] = function()
	with_worktree_picker({}, {}, function(fixture, calls, notices)
		fixture.refs = ref_row("refs/heads/deleted")
		fixture.select = 1
		herdr.open(false)
		assert_equal(notices[#notices].message:find("no longer exists", 1, true) ~= nil, true, "deleted local warning")
		assert_no_command(calls, { "worktree", "create" }, "deleted local does not start from HEAD")
	end)
	with_worktree_picker({
		{ branch = "deleted", path = "/tmp/deleted", is_linked_worktree = true },
	}, {}, function(fixture, calls, notices)
		fixture.choose = function()
			fixture.worktrees = {}
			return 1
		end
		herdr.open(false)
		assert_equal(
			notices[#notices].message:find("no longer exists", 1, true) ~= nil,
			true,
			"deleted checkout warning"
		)
		assert_no_command(calls, { "worktree", "open" }, "deleted checkout not reopened")
	end)
end

tests["fetch refresh preserves invocation directory and selected opening mode"] = function()
	for _, resume in ipairs({ false, true }) do
		with_worktree_picker({}, {}, function(fixture, calls)
			local cwd = vim.fn.getcwd()
			fixture.choose = function()
				if #fixture.menus == 1 then
					vim.api.nvim_set_current_dir(cwd .. "/config/nvim")
					return "Fetch remotes / refresh"
				end
				return "[remote] origin/feature/foo"
			end
			fixture.on_fetch = function()
				fixture.refs = ref_row("refs/remotes/origin/feature/foo")
			end
			herdr.open(resume)
			for _, call in ipairs(fixture.git_calls) do
				assert_equal(call.cwd, cwd, "fetch and selection use original cwd")
			end
			assert_equal(
				fixture.menus[2].prompt,
				resume and "Continue Herdr worktree" or "Open Herdr worktree",
				"opening mode retained"
			)
			if resume then
				local start = assert_command(calls, { "agent", "start" }, "continued agent after fetch")
				assert_equal(vim.tbl_contains(start, "resume"), true, "resume retained after fetch")
				assert_no_command(calls, { "pane", "run" }, "resume does not start Neovim")
			else
				assert_command(calls, { "pane", "run", "wNew:p1", "nvim ." }, "normal open after fetch")
				assert_no_command(
					calls,
					{ "agent", "start" },
					"fetch does not change normal opening into agent startup"
				)
			end
		end)
	end
end

tests["picker keeps its original repository across cwd changes"] = function()
	with_worktree_picker({}, {}, function(fixture, calls)
		remote_fixture(fixture)
		local cwd = vim.fn.getcwd()
		fixture.choose = function()
			vim.api.nvim_set_current_dir(cwd .. "/config/nvim")
			return 1
		end
		herdr.open(false)
		for _, call in ipairs(fixture.git_calls) do
			assert_equal(call.cwd, cwd, "captured Git cwd")
		end
		local create = assert_command(calls, { "worktree", "create" }, "captured checkout cwd")
		assert_equal(create[4], cwd, "captured Herdr cwd")
	end)
end

tests["checked out main master and feature branches match their upstream automatically"] = function()
	for _, name in ipairs({ "main", "master", "feature/foo" }) do
		with_worktree_picker({
			{
				branch = name,
				path = "/tmp/existing",
				open_workspace_id = "wExisting",
				is_linked_worktree = name == "feature/foo",
			},
		}, {}, function(fixture, calls, notices)
			local remote = "refs/remotes/origin/" .. name
			fixture.locals[name] = remote
			fixture.refs = ref_row("refs/heads/" .. name, nil, "same-tip", remote) .. ref_row(remote, nil, "same-tip")
			fixture.choose = function(items)
				for index, item in ipairs(items) do
					if item.kind == "remote" then
						return index
					end
				end
			end
			herdr.open(false)
			assert_equal(#fixture.menus, 1, "no name collision prompt")
			assert_equal(
				fixture.rows[2],
				"[remote] origin/" .. name .. " → " .. name .. " [open]",
				"destination shown"
			)
			assert_command(calls, { "workspace", "focus", "wExisting" }, "existing checkout focused")
			assert_no_command(calls, { "worktree", "create" }, "no duplicate checkout")
			assert_no_command(calls, { "agent", "start" }, "no duplicate agent")
			assert_no_command(git_commands(fixture), { "branch" }, "tracking already configured")
			assert_equal(
				notices[1].message,
				"worktree: " .. name .. " vs origin/" .. name .. ": equal (0 ahead, 0 behind)",
				"equal status"
			)
		end)
	end
end

tests["renamed upstream matches preserve equal ahead behind and diverged tips"] = function()
	for _, state in ipairs({
		{ output = "0\t0\n", label = "equal (0 ahead, 0 behind)" },
		{ output = "3\t0\n", label = "ahead (3 ahead, 0 behind)" },
		{ output = "0\t2\n", label = "behind (0 ahead, 2 behind)" },
		{ output = "3\t2\n", label = "diverged (3 ahead, 2 behind)" },
	}) do
		with_worktree_picker({
			{ branch = "review/foo", path = "/tmp/review", open_workspace_id = "wReview", is_linked_worktree = true },
		}, {}, function(fixture, calls, notices)
			remote_fixture(fixture)
			fixture.locals["review/foo"] = "refs/remotes/origin/feature/foo"
			fixture.status_output = state.output
			fixture.choose = remote_choice
			herdr.open(false)
			assert_command(calls, { "workspace", "focus", "wReview" }, "renamed checkout reused")
			assert_equal(
				notices[1].message,
				"worktree: review/foo vs origin/feature/foo: " .. state.label,
				"relative status"
			)
			assert_no_command(git_commands(fixture), { "branch" }, "branch tip and tracking preserved")
			assert_no_command(git_commands(fixture), { "merge" }, "no merge")
			assert_no_command(git_commands(fixture), { "reset" }, "no reset")
			assert_no_command(git_commands(fixture), { "rebase" }, "no rebase")
			assert_no_command(git_commands(fixture), { "checkout" }, "working files untouched")
		end)
	end
end

tests["upstream matching takes precedence over an identical untracked namesake"] = function()
	with_worktree_picker({
		{ branch = "review/foo", path = "/tmp/review", open_workspace_id = "wReview", is_linked_worktree = true },
	}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.locals["review/foo"] = "refs/remotes/origin/feature/foo"
		fixture.locals["feature/foo"], fixture.oids["feature/foo"] = "untracked", "remote-tip"
		fixture.choose = remote_choice
		herdr.open(false)
		assert_command(calls, { "workspace", "focus", "wReview" }, "upstream identity preferred")
		assert_equal(fixture.locals["feature/foo"], "untracked", "untracked namesake unchanged")
	end)
end

tests["identical untracked branch gains an upstream and reuses its checkout"] = function()
	with_worktree_picker({
		{ branch = "feature/foo", path = "/tmp/existing", open_workspace_id = "wExisting", is_linked_worktree = true },
	}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.locals["feature/foo"], fixture.oids["feature/foo"] = "untracked", "remote-tip"
		fixture.choose = remote_choice
		herdr.open(true)
		assert_command(git_commands(fixture), {
			"branch",
			"--set-upstream-to=refs/remotes/origin/feature/foo",
			"--",
			"feature/foo",
		}, "missing upstream configured")
		assert_equal(fixture.locals["feature/foo"], "refs/remotes/origin/feature/foo", "upstream attached")
		assert_command(calls, { "workspace", "focus", "wExisting" }, "same checkout reused")
		assert_no_command(calls, { "agent", "start" }, "existing agent retained")
	end)
end

tests["identical tips never overwrite a different configured upstream"] = function()
	with_worktree_picker({}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.locals["feature/foo"] = "refs/remotes/upstream/feature/foo"
		fixture.oids["feature/foo"] = "remote-tip"
		fixture.choose = function(items, opts)
			if not opts.prompt:find("already exists", 1, true) then
				return remote_choice(items)
			end
		end
		herdr.open(false)
		assert_equal(#fixture.menus, 2, "conflicting upstream still needs a choice")
		assert_equal(fixture.locals["feature/foo"], "refs/remotes/upstream/feature/foo", "different upstream preserved")
		assert_no_command(git_commands(fixture), { "branch" }, "no implicit upstream rewrite")
		assert_no_command(calls, { "worktree", "create" }, "cancel leaves checkout alone")
	end)
end

tests["missing configured remote is preserved even when tips are identical"] = function()
	with_worktree_picker({}, {}, function(fixture, calls)
		remote_fixture(fixture)
		fixture.locals["feature/foo"], fixture.oids["feature/foo"] = "missing remote", "remote-tip"
		fixture.configured["feature/foo"] = true
		fixture.choose = function(items, opts)
			if not opts.prompt:find("already exists", 1, true) then
				return remote_choice(items)
			end
		end
		herdr.open(false)
		assert_equal(#fixture.menus, 2, "unresolvable upstream still requires a choice")
		assert_equal(fixture.locals["feature/foo"], "missing remote", "configured relationship preserved")
		assert_no_command(git_commands(fixture), { "branch" }, "no implicit upstream replacement")
		assert_no_command(calls, { "worktree", "create" }, "cancel leaves branch alone")
	end)
end

tests["matching branches without a checkout preserve editor or continuation mode"] = function()
	for _, resume in ipairs({ false, true }) do
		with_worktree_picker({}, {}, function(fixture, calls)
			remote_fixture(fixture)
			fixture.locals["review/foo"] = "refs/remotes/origin/feature/foo"
			fixture.choose = remote_choice
			herdr.open(resume)
			local create = assert_command(calls, { "worktree", "create" }, "existing branch checkout")
			assert_equal(create[vim.fn.index(create, "--branch") + 2], "review/foo", "reuse renamed local branch")
			if resume then
				local start = assert_command(calls, { "agent", "start" }, "continue matched branch")
				assert_equal(vim.tbl_contains(start, "resume"), true, "continuation retained")
			else
				assert_command(calls, { "pane", "run", "wNew:p1", "nvim ." }, "matched branch opens Neovim")
				assert_no_command(calls, { "agent", "start" }, "matched branch does not start Codex")
			end
			assert_no_command(git_commands(fixture), { "branch" }, "existing upstream retained")
		end)
	end
end

tests["multiple upstream matches offer local destinations and respect cancellation"] = function()
	for _, cancel in ipairs({ false, true }) do
		with_worktree_picker({
			{ branch = "review/two", path = "/tmp/two", open_workspace_id = "wTwo", is_linked_worktree = true },
		}, {}, function(fixture, calls)
			remote_fixture(fixture)
			fixture.locals["review/one"] = "refs/remotes/origin/feature/foo"
			fixture.locals["review/two"] = "refs/remotes/origin/feature/foo"
			fixture.choose = function(items, opts)
				if opts.prompt:find("Local branches matching", 1, true) then
					if not cancel then
						return "review/two [open]"
					end
					return nil
				end
				return remote_choice(items)
			end
			herdr.open(false)
			assert_equal(fixture.rows, { "review/one", "review/two [open]" }, "destination chooser")
			assert_no_command(calls, { "worktree", "create" }, "no new checkout")
			if cancel then
				assert_no_command(calls, { "workspace", "focus" }, "cancel matching chooser")
			else
				assert_command(calls, { "workspace", "focus", "wTwo" }, "selected matching checkout")
			end
		end)
	end
end

tests["changed upstream during a destination choice prevents stale reconciliation"] = function()
	with_worktree_picker({}, {}, function(fixture, calls, notices)
		remote_fixture(fixture)
		fixture.locals["review/one"] = "refs/remotes/origin/feature/foo"
		fixture.locals["review/two"] = "refs/remotes/origin/feature/foo"
		fixture.choose = function(items, opts)
			if opts.prompt:find("Local branches matching", 1, true) then
				fixture.locals["review/one"] = "refs/remotes/upstream/other"
				return 1
			end
			return remote_choice(items)
		end
		herdr.open(false)
		assert_equal(
			notices[#notices].message:find("relationship changed", 1, true) ~= nil,
			true,
			"stale relationship warning"
		)
		assert_no_command(calls, { "worktree", "create" }, "no stale checkout")
		assert_no_command(git_commands(fixture), { "branch" }, "new upstream preserved")
	end)
end

tests["remote disappearance and ref lookup failures do not create branches"] = function()
	for _, failure in ipairs({ "missing", "lookup" }) do
		with_worktree_picker({}, {}, function(fixture, calls, notices)
			remote_fixture(fixture)
			fixture.choose = function(items)
				fixture.refs = ""
				fixture.refs_error = failure == "lookup"
				return remote_choice(items)
			end
			herdr.open(false)
			assert_equal(#notices > 0, true, "failure reported")
			assert_no_command(git_commands(fixture), { "branch" }, "no branch after unavailable remote")
			assert_no_command(calls, { "worktree", "create" }, "no checkout after unavailable remote")
		end)
	end
end

tests["upstream configuration failure aborts opening but comparison failure only warns"] = function()
	with_worktree_picker({}, {}, function(fixture, calls, notices)
		remote_fixture(fixture)
		fixture.locals["feature/foo"], fixture.oids["feature/foo"] = "untracked", "remote-tip"
		fixture.tracking_error, fixture.choose = true, remote_choice
		herdr.open(false)
		assert_equal(
			notices[#notices].message:find("cannot write branch configuration", 1, true) ~= nil,
			true,
			"tracking failure"
		)
		assert_equal(fixture.locals["feature/foo"], "untracked", "failed configuration preserved")
		assert_no_command(calls, { "worktree", "create" }, "no checkout after tracking failure")
	end)
	for _, invalid in ipairs({ false, true }) do
		with_worktree_picker({
			{ branch = "review/foo", path = "/tmp/review", open_workspace_id = "wReview", is_linked_worktree = true },
		}, {}, function(fixture, calls, notices)
			remote_fixture(fixture)
			fixture.locals["review/foo"] = "refs/remotes/origin/feature/foo"
			fixture.status_code = invalid and 0 or 1
			fixture.status_output = invalid and "invalid" or ""
			fixture.choose = remote_choice
			herdr.open(false)
			assert_equal(notices[1].level, vim.log.levels.WARN, "comparison warning")
			assert_command(calls, { "workspace", "focus", "wReview" }, "open known match despite status failure")
		end)
	end
end

tests["real Git tracking and reconciliation preserve commits and dirty worktrees"] = function()
	local temp = vim.fn.tempname()
	assert_equal(temp ~= "", true, "a writable temporary directory is required for the real Git fixture")
	local repo = temp .. "/repo space ' $literal"
	local function git(args, cwd)
		local result = vim.system(
			vim.list_extend({
				"git",
				"-c",
				"user.name=Test",
				"-c",
				"user.email=test@example.com",
			}, args),
			{ cwd = cwd or repo, text = true }
		):wait()
		assert_equal(result.code, 0, "fixture Git " .. table.concat(args, " ") .. ": " .. result.stderr)
		return vim.trim(result.stdout)
	end
	local ok, err = xpcall(function()
		vim.fn.mkdir(repo, "p")
		git({ "init", "-q", "-b", "main" })
		git({ "commit", "--allow-empty", "-qm", "initial" })
		git({ "config", "branch.autoSetupMerge", "false" })
		git({ "remote", "add", "origin", repo })
		git({ "remote", "add", "upstream", repo })
		local tip = git({ "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "remote tip" })
		git({ "update-ref", "refs/remotes/origin/feature/foo", tip })
		git({ "update-ref", "refs/remotes/upstream/feature/foo", tip })
		with_worktree_picker({
			{ branch = "main", path = repo, is_linked_worktree = false, open_workspace_id = "wMain" },
		}, {}, function(fixture, calls, notices)
			vim.api.nvim_set_current_dir(repo)
			herdr._test.git = nil -- Exercise production Git subprocesses.
			local checkouts = {}
			fixture.on_create = function(args)
				local branch = args[vim.fn.index(args, "--branch") + 2]
				local checkout = temp .. "/checkout-" .. tostring(#checkouts + 1)
				git({ "worktree", "add", "-q", "--", checkout, branch })
				table.insert(checkouts, checkout)
				local id = "wCheckout" .. #checkouts
				table.insert(fixture.worktrees, {
					branch = branch,
					path = checkout,
					is_linked_worktree = true,
					open_workspace_id = id,
				})
				return { workspace = { workspace_id = id, cwd = checkout } }
			end
			fixture.input = "review/foo"
			fixture.choose = function(items, opts)
				if opts.prompt:find("already exists", 1, true) then
					return 2
				end
				return remote_choice(items)
			end
			for index, branch in ipairs({ "feature/foo", "review/foo" }) do
				herdr.open(false)
				assert_equal(
					vim.wait(5000, function()
						return #checkouts == index
					end),
					true,
					"real tracking checkout completed"
				)
				assert_equal(git({ "rev-parse", "HEAD" }, checkouts[index]), tip, "selected remote commit")
				assert_equal(
					git({ "rev-parse", "--symbolic-full-name", branch .. "@{upstream}" }),
					"refs/remotes/origin/feature/foo",
					"selected upstream"
				)
				assert_equal(git({ "config", "branch." .. branch .. ".remote" }), "origin", "remote configured")
				assert_equal(
					git({ "config", "branch." .. branch .. ".merge" }),
					"refs/heads/feature/foo",
					"merge configured"
				)
				if index == 1 then
					-- Keep the collision/alternative-name path covered despite automatic matching.
					git({ "branch", "--set-upstream-to=refs/remotes/upstream/feature/foo", "--", branch })
				end
			end
			local dirty_file = checkouts[2] .. "/untracked.txt"
			vim.fn.writefile({ "preserve my work" }, dirty_file)
			local next_tip = git({ "commit-tree", tip .. "^{tree}", "-p", tip, "-m", "advanced remote" })
			git({ "update-ref", "refs/remotes/origin/feature/foo", next_tip })
			fixture.choose = remote_choice
			local function focused(id)
				for _, args in ipairs(calls) do
					if vim.deep_equal(args, { "workspace", "focus", id }) then
						return true
					end
				end
				return false
			end
			herdr.open(true)
			assert_equal(
				vim.wait(5000, function()
					return focused("wCheckout2")
				end),
				true,
				"renamed tracking checkout reused"
			)
			assert_equal(#checkouts, 2, "no duplicate checkout")
			assert_equal(git({ "rev-parse", "HEAD" }, checkouts[2]), tip, "behind local tip unchanged")
			assert_equal(vim.fn.readfile(dirty_file), { "preserve my work" }, "dirty work retained")
			assert_equal(git({ "config", "branch.feature/foo.remote" }), "upstream", "other upstream unchanged")
			local behind_reported = false
			for _, notice in ipairs(notices) do
				behind_reported = behind_reported or notice.message:find("behind (0 ahead, 1 behind)", 1, true) ~= nil
			end
			assert_equal(behind_reported, true, "real behind counts")

			local main_tip = git({ "rev-parse", "refs/heads/main" })
			git({ "update-ref", "refs/remotes/origin/main", main_tip })
			fixture.choose = function(items)
				for index, item in ipairs(items) do
					if item.ref == "refs/remotes/origin/main" then
						return index
					end
				end
				error("origin/main not offered")
			end
			herdr.open(false)
			assert_equal(
				vim.wait(5000, function()
					return focused("wMain")
				end),
				true,
				"primary checkout reconciled"
			)
			assert_equal(git({ "config", "branch.main.remote" }), "origin", "missing main remote configured")
			assert_equal(git({ "config", "branch.main.merge" }), "refs/heads/main", "missing main upstream configured")
			assert_equal(git({ "rev-parse", "refs/heads/main" }), main_tip, "main tip unchanged")
			assert_equal(#checkouts, 2, "primary checkout reused")
		end)
	end, debug.traceback)
	vim.fn.delete(temp, "rf")
	if not ok then
		error(err)
	end
end

tests["agent navigation wraps and latest attention uses state sequence"] = function()
	local calls = {}
	local old_pane = vim.env.HERDR_PANE_ID
	vim.env.HERDR_PANE_ID = "w1:p2"
	herdr._test.run = function(args, opts)
		table.insert(calls, vim.deepcopy(args))
		if args[1] == "agent" and args[2] == "list" then
			opts.on_success(response({
				agents = {
					{ name = "first", pane_id = "w1:p1", agent_status = "done", state_change_seq = 4 },
					{ name = "second", pane_id = "w1:p2", agent_status = "idle", state_change_seq = 8 },
					{ name = "third", pane_id = "w1:p3", agent_status = "blocked", state_change_seq = 12 },
				},
			}))
		elseif opts.on_success then
			opts.on_success(response({}))
		end
	end

	herdr.cycle_agent(1)
	assert_command(calls, { "agent", "focus", "third" }, "next agent")
	herdr.focus_latest_attention()
	local focus_count = 0
	for _, args in ipairs(calls) do
		if vim.deep_equal(args, { "agent", "focus", "third" }) then
			focus_count = focus_count + 1
		end
	end
	assert_equal(focus_count, 2, "latest blocked agent")

	vim.env.HERDR_PANE_ID = old_pane
	herdr._test.run = nil
end

tests["agent dashboard resolves normal, tagged, legacy, and stale pane targets"] = function()
	local snapshot = {
		workspaces = { { workspace_id = "w1", label = "project" } },
		tabs = { { tab_id = "w1:t1", workspace_id = "w1", title = "editor" } },
		panes = {
			{ pane_id = "w1:p1", tab_id = "w1:t1", cwd = "/tmp/project" },
			{ pane_id = "w1:p2", tab_id = "w1:t1" },
			{ pane_id = "w1:p3", tab_id = "w1:t1" },
			{ pane_id = "w1:p4", tab_id = "w1:t1" },
			{ pane_id = "w1:p5", tab_id = "w1:t1" },
		},
		layouts = {
			{
				tab_id = "w1:t1",
				panes = {
					{ pane_id = "w1:p1", rect = { x = 0, y = 0, width = 60, height = 40 } },
					{ pane_id = "w1:p3", rect = { x = 60, y = 0, width = 40, height = 40 } },
					{ pane_id = "w1:p4", rect = { x = 0, y = 40, width = 60, height = 30 } },
					{ pane_id = "w1:p5", rect = { x = 60, y = 40, width = 40, height = 30 } },
				},
			},
		},
		agents = {
			{
				name = "reviewer",
				pane_id = "w1:p2",
				tab_id = "w1:t1",
				workspace_id = "w1",
				agent_status = "working",
				title = "Review changes",
			},
			{
				name = "nvim-codex-tagged",
				pane_id = "w1:p3",
				tab_id = "w1:t1",
				workspace_id = "w1",
				agent_status = "blocked",
				tokens = { "nvim_host_pane=w1:p1" },
			},
			{
				name = "nvim-codex-legacy",
				pane_id = "w1:p5",
				tab_id = "w1:t1",
				workspace_id = "w1",
				agent_status = "idle",
			},
			{
				name = "nvim-codex-stale",
				pane_id = "w1:p3",
				tab_id = "w1:t1",
				workspace_id = "w1",
				tokens = { nvim_host_pane = "w1:p99" },
			},
		},
	}
	local items = herdr._test.build_agent_items(snapshot)
	assert_equal(#items, 4, "item count")
	assert_equal(items[1].target_pane_id, "w1:p2", "normal agent pane")
	assert_equal(items[1].targets_nvim, false, "normal target kind")
	assert_equal(items[2].target_pane_id, "w1:p1", "tagged host pane")
	assert_equal(items[2].targets_nvim, true, "tagged target kind")
	assert_equal(items[3].target_pane_id, "w1:p4", "legacy left pane")
	assert_equal(items[3].targets_nvim, true, "legacy target kind")
	assert_equal(items[4].target_pane_id, "w1:p3", "stale metadata fallback")
	assert_equal(items[4].targets_nvim, false, "stale target kind")
	assert_equal(items[1].workspace_label, "project", "workspace label")
	assert_equal(items[1].tab_label, "editor", "tab label")
	assert_equal(items[1].text:find("Review changes", 1, true) ~= nil, true, "searchable title")
end

tests["agent dashboard previews and focuses the resolved target"] = function()
	local calls = {}
	local preview_command
	local preview_opts
	local preview_window_opts
	local old_preview = package.loaded["snacks.picker.preview"]
	package.loaded["snacks.picker.preview"] = {
		cmd = function(command, _, opts)
			preview_command = command
			preview_opts = opts
		end,
	}
	local preview = {
		reset = function() end,
		minimal = function() end,
		set_title = function() end,
		wo = function(_, opts)
			preview_window_opts = opts
		end,
	}
	local preview_win = vim.api.nvim_get_current_win()
	herdr._test.preview_agent({
		item = {
			target_pane_id = "w1:p1",
			workspace_label = "project",
			tab_label = "editor",
			name = "nvim-codex-tagged",
		},
		preview = preview,
		win = preview_win,
	})
	package.loaded["snacks.picker.preview"] = old_preview
	assert_equal(preview_command, {
		vim.fn.stdpath("config") .. "/bin/herdr-pane-preview",
		"w1:p1",
		tostring(vim.api.nvim_win_get_width(preview_win)),
	}, "preview command")
	assert_equal(preview_opts, { term = false, ansi = true }, "ANSI preview renderer")
	assert_equal(preview_window_opts, { wrap = false }, "preview wrapping")

	herdr._test.run = function(args, opts)
		table.insert(calls, vim.deepcopy(args))
		if args[1] == "pane" then
			opts.on_error({ code = 1, stderr = "stale", stdout = "" }, "stale")
		elseif opts.on_success then
			opts.on_success(response({}))
		end
	end
	herdr._test.focus_agent_item({
		name = "nvim-codex-tagged",
		agent_pane_id = "w1:p2",
		target_pane_id = "w1:p1",
		targets_nvim = true,
	})
	assert_equal(calls[1], { "pane", "zoom", "w1:p1", "--on" }, "zoom host")
	assert_equal(calls[2], { "agent", "focus", "nvim-codex-tagged" }, "focus fallback")

	herdr._test.focus_agent_item({
		name = "reviewer",
		agent_pane_id = "w1:p2",
		target_pane_id = "w1:p2",
		targets_nvim = false,
	})
	assert_equal(calls[3], { "agent", "focus", "reviewer" }, "normal focus")
	herdr._test.run = nil
end

tests["dashboard loads one snapshot into Snacks"] = function()
	local picker_opts
	local old_snacks = _G.Snacks
	_G.Snacks = { picker = {
		pick = function(opts)
			picker_opts = opts
		end,
	} }
	herdr._test.run = function(args, opts)
		assert_equal(args, { "api", "snapshot" }, "snapshot command")
		opts.on_success(response({
			snapshot = {
				workspaces = { { workspace_id = "w1", label = "project" } },
				tabs = { { tab_id = "w1:t1", title = "main" } },
				panes = { { pane_id = "w1:p1", tab_id = "w1:t1" } },
				layouts = {},
				agents = {
					{ name = "reviewer", pane_id = "w1:p1", tab_id = "w1:t1", workspace_id = "w1" },
				},
			},
		}))
	end
	herdr.select_workspace()
	assert_equal(picker_opts.title, "Herdr Agents", "picker title")
	assert_equal(#picker_opts.items, 1, "picker items")
	assert_equal(picker_opts.items[1].name, "reviewer", "picker agent")
	herdr._test.run = nil
	_G.Snacks = old_snacks
end

for name, test in pairs(tests) do
	-- Legacy picker tests have no refs; never read the developer's repository.
	herdr._test.git = function(_, _, callback)
		callback({ code = 0, stdout = "", stderr = "" })
	end
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

herdr._test.git = nil
print("worktree_herdr_spec.lua: ok")
