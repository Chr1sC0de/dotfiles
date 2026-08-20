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
				worktrees = { { branch = "feature", path = "/tmp/repo-feature", is_linked_worktree = true } },
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
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("worktree_herdr_spec.lua: ok")
