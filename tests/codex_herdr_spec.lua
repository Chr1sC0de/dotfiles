vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:append(".")
package.path = table.concat({
	vim.fn.getcwd() .. "/config/nvim/lua/?.lua",
	vim.fn.getcwd() .. "/config/nvim/lua/?/init.lua",
	package.path,
}, ";")

local herdr = require("codex.herdr")

local function assert_equal(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_contains(values, expected, label)
	for _, value in ipairs(values) do
		if value == expected then
			return
		end
	end
	error(string.format("%s: expected %q in %s", label, expected, vim.inspect(values)))
end

local tests = {}

local function workspace_response(workspace_id, tab_id, pane_id)
	return {
		code = 0,
		stderr = "",
		stdout = vim.json.encode({
			id = "cli:workspace:create",
			result = {
				workspace = { workspace_id = workspace_id },
				tab = { tab_id = tab_id },
				root_pane = { pane_id = pane_id },
			},
		}),
	}
end

tests["agent names are valid and bounded"] = function()
	local name = herdr.agent_name(123456789)
	assert_equal(name:match("^[a-z][a-z0-9_-]*$") ~= nil, true, "agent name syntax")
	assert_equal(#name <= 32, true, "agent name length")
end

tests["Codex workspace creation is persistent and unfocused"] = function()
	local args = herdr.workspace_create_args("/tmp/project with spaces")
	assert_equal(args, {
		"workspace",
		"create",
		"--cwd",
		"/tmp/project with spaces",
		"--label",
		"Codex",
		"--no-focus",
	}, "workspace create args")

	local workspace_id, tab_id, pane_id =
		herdr.parse_workspace_create(workspace_response("w7", "w7:t1", "w7:p1").stdout)
	assert_equal(workspace_id, "w7", "workspace id")
	assert_equal(tab_id, "w7:t1", "home tab id")
	assert_equal(pane_id, "w7:p1", "home pane id")
end

tests["Codex workspace state is isolated by Herdr socket"] = function()
	local old_socket_path = vim.env.HERDR_SOCKET_PATH
	vim.env.HERDR_SOCKET_PATH = "/tmp/herdr-one.sock"
	local first = herdr.workspace_state_path()
	vim.env.HERDR_SOCKET_PATH = "/tmp/herdr-two.sock"
	local second = herdr.workspace_state_path()
	vim.env.HERDR_SOCKET_PATH = old_socket_path

	assert_equal(first ~= second, true, "distinct state paths")
	assert_equal(first:match("workspace%-%x+%.state$") ~= nil, true, "hashed state filename")
end

tests["Codex workspace resolver reuses persisted state and recreates stale state"] = function()
	local old_socket_path = vim.env.HERDR_SOCKET_PATH
	local old_workspace_state_path = herdr.workspace_state_path
	local state_path = vim.fn.tempname() .. ".state"
	herdr.workspace_state_path = function()
		return state_path
	end
	vim.env.HERDR_SOCKET_PATH = vim.fn.tempname() .. ".sock"
	herdr._test.reset_workspace_state(true)

	local create_count = 0
	local get_count = 0
	herdr._test.run = function(args, opts)
		local command = args[1] .. " " .. args[2]
		if command == "workspace create" then
			create_count = create_count + 1
			opts.on_success(workspace_response("w7", "w7:t1", "w7:p1"))
		elseif command == "workspace get" then
			get_count = get_count + 1
			if args[3] == "w7" then
				opts.on_error({ code = 1, stdout = "", stderr = "missing" }, "missing")
			else
				opts.on_success({ code = 0, stdout = "{}", stderr = "" })
			end
		elseif command == "tab rename" then
			assert_equal(args, { "tab", "rename", "w7:t1", "home" }, "home tab rename")
		end
	end

	local first_workspace = nil
	herdr.ensure_codex_workspace("/tmp/project", {
		on_success = function(workspace_id)
			first_workspace = workspace_id
		end,
	})
	assert_equal(first_workspace, "w7", "created workspace")
	assert_equal(vim.fn.filereadable(herdr.workspace_state_path()), 1, "workspace state file")

	herdr._test.reset_workspace_state(false)
	local reused_workspace = nil
	herdr._test.run = function(args, opts)
		local command = args[1] .. " " .. args[2]
		if command == "workspace get" then
			get_count = get_count + 1
			opts.on_success({ code = 0, stdout = "{}", stderr = "" })
		end
	end
	herdr.ensure_codex_workspace("/tmp/project", {
		on_success = function(workspace_id)
			reused_workspace = workspace_id
		end,
	})
	assert_equal(reused_workspace, "w7", "reused workspace")

	herdr._test.reset_workspace_state(false)
	local recreated_workspace = nil
	herdr._test.run = function(args, opts)
		local command = args[1] .. " " .. args[2]
		if command == "workspace get" then
			get_count = get_count + 1
			opts.on_error({ code = 1, stdout = "", stderr = "missing" }, "missing")
		elseif command == "workspace create" then
			create_count = create_count + 1
			opts.on_success(workspace_response("w8", "w8:t1", "w8:p1"))
		end
	end
	herdr.ensure_codex_workspace("/tmp/project", {
		on_success = function(workspace_id)
			recreated_workspace = workspace_id
		end,
	})

	assert_equal(recreated_workspace, "w8", "recreated workspace")
	assert_equal(create_count, 2, "workspace create count")
	assert_equal(get_count, 2, "workspace validation count")

	herdr._test.run = nil
	herdr._test.reset_workspace_state(true)
	herdr.workspace_state_path = old_workspace_state_path
	vim.env.HERDR_SOCKET_PATH = old_socket_path
end

tests["Codex workspace resolver queues concurrent launch requests"] = function()
	local old_socket_path = vim.env.HERDR_SOCKET_PATH
	local old_workspace_state_path = herdr.workspace_state_path
	local state_path = vim.fn.tempname() .. ".state"
	herdr.workspace_state_path = function()
		return state_path
	end
	vim.env.HERDR_SOCKET_PATH = vim.fn.tempname() .. ".sock"
	herdr._test.reset_workspace_state(true)

	local create_opts = nil
	herdr._test.run = function(args, opts)
		local command = args[1] .. " " .. args[2]
		if command == "workspace create" then
			create_opts = opts
		end
	end

	local resolved = {}
	for index = 1, 2 do
		local slot = index
		herdr.ensure_codex_workspace("/tmp/project", {
			on_success = function(workspace_id)
				resolved[slot] = workspace_id
			end,
		})
	end
	assert_equal(create_opts ~= nil, true, "creation pending")
	create_opts.on_success(workspace_response("w9", "w9:t1", "w9:p1"))
	assert_equal(resolved, { "w9", "w9" }, "queued callbacks")

	herdr._test.run = nil
	herdr._test.reset_workspace_state(true)
	herdr.workspace_state_path = old_workspace_state_path
	vim.env.HERDR_SOCKET_PATH = old_socket_path
end

tests["Codex workspace creation failure reaches every queued launch"] = function()
	local old_socket_path = vim.env.HERDR_SOCKET_PATH
	local old_workspace_state_path = herdr.workspace_state_path
	local state_path = vim.fn.tempname() .. ".state"
	herdr.workspace_state_path = function()
		return state_path
	end
	vim.env.HERDR_SOCKET_PATH = vim.fn.tempname() .. ".sock"
	herdr._test.reset_workspace_state(true)

	local create_opts = nil
	herdr._test.run = function(args, opts)
		if args[1] == "workspace" and args[2] == "create" then
			create_opts = opts
		end
	end

	local errors = {}
	for index = 1, 2 do
		local slot = index
		herdr.ensure_codex_workspace("/tmp/project", {
			on_error = function(_, message)
				errors[slot] = message
			end,
		})
	end
	create_opts.on_error({ code = 1, stdout = "", stderr = "failed" }, "failed")
	assert_equal(errors, { "failed", "failed" }, "queued errors")

	herdr._test.run = nil
	herdr._test.reset_workspace_state(true)
	herdr.workspace_state_path = old_workspace_state_path
	vim.env.HERDR_SOCKET_PATH = old_socket_path
end

tests["ephemeral labels describe the action target and task"] = function()
	local label = herdr.ephemeral_label({
		action = "command",
		id = 13,
		instruction = "  explain\n  the diagnostics lifecycle  ",
		path = "/tmp/project/context.lua",
	})

	assert_equal(label, "cmd #13 · context.lua · explain the diagnostics lifecycle", "descriptive label")
end

tests["ephemeral labels are unicode safe and bounded"] = function()
	local label = herdr.ephemeral_label({
		action = "edit",
		id = 12,
		instruction = string.rep("ø", 80),
		path = "",
	})

	assert_equal(vim.fn.strchars(label), 64, "label character count")
	assert_equal(label:sub(-3), "…", "label ellipsis")
	assert_equal(label:find("edit #12 · %[No Name%]", 1) ~= nil, true, "stable label prefix")
end

tests["tab creation preserves cwd and injects route state"] = function()
	local args = herdr.tab_create_args({
		codex_real_bin = "/usr/local/bin/codex",
		cwd = "/tmp/project with spaces",
		herdr_real_bin = "/usr/local/bin/herdr",
		herdr_route_path = "/tmp/codex.route",
		herdr_tab_label = "codex-4",
		herdr_wrapper_dir = "/tmp/codex-wrapper",
	}, "w7")

	assert_equal(args[1], "tab", "command group")
	assert_equal(args[2], "create", "command")
	assert_contains(args, "w7", "workspace")
	assert_contains(args, "/tmp/project with spaces", "cwd")
	assert_contains(args, "CODEX_NVIM_STATE_FILE=/tmp/codex.route", "route env")
	assert_contains(args, "CODEX_THREAD_ID=", "thread id reset")
	assert_contains(args, "CODEX_REAL_BIN=/usr/local/bin/codex", "real Codex binary")
	assert_contains(args, "CODEX_HERDR_BIN=/usr/local/bin/herdr", "Herdr binary")
	local path_found = false
	for _, value in ipairs(args) do
		if value:match("^PATH=/tmp/codex%-wrapper:") then
			path_found = true
			break
		end
	end
	assert_equal(path_found, true, "wrapper PATH")
	assert_contains(args, "--no-focus", "focus policy")
end

tests["tab creation response exposes stable ids"] = function()
	local tab_id, pane_id = herdr.parse_tab_create(vim.json.encode({
		id = "cli:tab:create",
		result = {
			tab = { tab_id = "w7:t3" },
			root_pane = { pane_id = "w7:p9" },
		},
	}))

	assert_equal(tab_id, "w7:t3", "tab id")
	assert_equal(pane_id, "w7:p9", "pane id")
end

tests["ephemeral tab creation is unfocused and carries runner state"] = function()
	local args = herdr.ephemeral_tab_create_args({
		action = "edit",
		cwd = "/tmp/project with spaces",
		herdr_workspace_id = "w7",
		id = 12,
		instruction = "fix cancellation",
		model = "gpt-test",
		path = "/tmp/project/jobs.lua",
		prompt_path = "/tmp/prompt",
		reasoning_effort = "high",
		sandbox = "workspace-write",
		status_path = "/tmp/status",
		stderr_path = "/tmp/stderr",
		stdout_path = "/tmp/stdout",
	})

	assert_equal(args[1], "tab", "command group")
	assert_equal(args[2], "create", "command")
	assert_contains(args, "edit #12 · jobs.lua · fix cancellation", "label")
	assert_contains(args, "CODEX_EPHEMERAL_PROMPT_PATH=/tmp/prompt", "prompt state")
	assert_contains(args, "CODEX_EPHEMERAL_STDOUT_PATH=/tmp/stdout", "stdout state")
	assert_contains(args, "CODEX_EPHEMERAL_STDERR_PATH=/tmp/stderr", "stderr state")
	assert_contains(args, "CODEX_EPHEMERAL_STATUS_PATH=/tmp/status", "status state")
	assert_contains(args, "CODEX_EPHEMERAL_SANDBOX=workspace-write", "sandbox")
	assert_contains(args, "CODEX_EPHEMERAL_MODEL=gpt-test", "model")
	assert_contains(args, "CODEX_EPHEMERAL_REASONING_EFFORT=high", "reasoning effort")
	assert_contains(args, "--no-focus", "focus policy")
end

tests["ephemeral runner targets the created pane"] = function()
	local args = herdr.ephemeral_pane_run_args({ herdr_pane_id = "w7:p9" })

	assert_equal(args[1], "pane", "command group")
	assert_equal(args[2], "run", "command")
	assert_equal(args[3], "w7:p9", "pane id")
	assert_equal(args[4]:find("ephemeral", 1, true) ~= nil, true, "runner path")
end

tests["chat and ephemeral launches target the resolved Codex workspace"] = function()
	local old_ensure_codex_workspace = herdr.ensure_codex_workspace
	local tab_workspaces = {}
	local successful_launches = 0
	herdr.ensure_codex_workspace = function(_, opts)
		opts.on_success("wCodex")
	end
	herdr._test.run = function(args, opts)
		local command = args[1] .. " " .. args[2]
		if command == "tab create" then
			for index, value in ipairs(args) do
				if value == "--workspace" then
					table.insert(tab_workspaces, args[index + 1])
					break
				end
			end
			opts.on_success({
				code = 0,
				stderr = "",
				stdout = vim.json.encode({
					result = {
						tab = { tab_id = "wCodex:t2" },
						root_pane = { pane_id = "wCodex:p2" },
					},
				}),
			})
		elseif command == "pane run" or command == "agent start" then
			successful_launches = successful_launches + 1
			opts.on_success({ code = 0, stdout = "", stderr = "" })
		end
	end

	herdr.launch_ephemeral({
		action = "command",
		cwd = "/tmp/project",
		id = 1,
		instruction = "explain this",
		path = "/tmp/project/sample.lua",
		prompt_path = "/tmp/prompt",
		sandbox = "read-only",
		status_path = "/tmp/status",
		stderr_path = "/tmp/stderr",
		stdout_path = "/tmp/stdout",
	}, { on_success = function() end })
	herdr.create_backing_agent({
		codex_real_bin = "/usr/bin/codex",
		cwd = "/tmp/project",
		herdr_agent_name = "nvim-codex-123-1",
		herdr_real_bin = "/usr/bin/herdr",
		herdr_route_path = "/tmp/route",
		herdr_tab_label = "codex-1",
		herdr_wrapper_dir = "/tmp/wrapper",
	}, { on_success = function() end })

	herdr._test.run = nil
	herdr.ensure_codex_workspace = old_ensure_codex_workspace
	assert_equal(tab_workspaces, { "wCodex", "wCodex" }, "resolved tab workspaces")
	assert_equal(successful_launches, 2, "launch count")
end

tests["agent start targets the backing pane"] = function()
	local args = herdr.agent_start_args({
		cwd = "/tmp/project",
		herdr_agent_name = "nvim-codex-123-2",
		herdr_pane_id = "w7:p9",
	})

	assert_equal(args, {
		"agent",
		"start",
		"nvim-codex-123-2",
		"--kind",
		"codex",
		"--pane",
		"w7:p9",
		"--timeout",
		"60000",
		"--",
		"--cd",
		"/tmp/project",
	}, "agent start args")
end

tests["reattach candidates span workspaces and require route state"] = function()
	local route_path = vim.fn.tempname()
	vim.fn.writefile({ "server", "1", "token" }, route_path)

	local original_route_path = herdr.route_path
	herdr.route_path = function(name)
		if name == "nvim-codex-123-2" or name == "nvim-codex-123-3" then
			return route_path
		end
		return route_path .. ".missing"
	end

	local candidates = herdr.filter_agents({
		{ name = "nvim-codex-123-2", agent = "codex", workspace_id = "w7", pane_id = "w7:p9" },
		{ name = "nvim-codex-123-3", agent = "codex", workspace_id = "w8", pane_id = "w8:p1" },
		{ name = "reviewer", agent = "codex", workspace_id = "w7", pane_id = "w7:p2" },
	}, {})

	herdr.route_path = original_route_path
	vim.fn.delete(route_path)
	assert_equal(#candidates, 2, "candidate count")
	assert_equal(candidates[1].name, "nvim-codex-123-2", "candidate name")
	assert_equal(candidates[2].name, "nvim-codex-123-3", "cross-workspace candidate")
end

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("codex_herdr_spec.lua: ok")
