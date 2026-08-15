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

tests["agent names are valid and bounded"] = function()
	local name = herdr.agent_name(123456789)
	assert_equal(name:match("^[a-z][a-z0-9_-]*$") ~= nil, true, "agent name syntax")
	assert_equal(#name <= 32, true, "agent name length")
end

tests["chat split targets the Neovim pane and starts focused"] = function()
	local args = herdr.pane_split_args({
		codex_real_bin = "/usr/local/bin/codex",
		cwd = "/tmp/project with spaces",
		herdr_host_pane_id = "w7:p1",
		herdr_real_bin = "/usr/local/bin/herdr",
		herdr_route_path = "/tmp/codex.route",
		herdr_wrapper_dir = "/tmp/codex-wrapper",
	})
	assert_equal(args[1], "pane", "command group")
	assert_equal(args[2], "split", "command")
	assert_equal(args[3], "w7:p1", "host pane")
	assert_contains(args, "right", "direction")
	assert_contains(args, "0.4", "ratio")
	assert_contains(args, "/tmp/project with spaces", "cwd")
	assert_contains(args, "CODEX_NVIM_STATE_FILE=/tmp/codex.route", "route env")
	assert_contains(args, "CODEX_THREAD_ID=", "thread reset")
	assert_contains(args, "--focus", "startup visibility")
end

tests["pane split response yields the backing pane"] = function()
	local pane_id = herdr.parse_pane_split(vim.json.encode({ result = { pane = { pane_id = "w7:p9" } } }))
	assert_equal(pane_id, "w7:p9", "pane id")
	local missing, err = herdr.parse_pane_split("{}")
	assert_equal(missing, nil, "invalid response")
	assert_equal(type(err), "string", "invalid response message")
end

tests["chat launch starts visibly then returns to and zooms Neovim"] = function()
	local calls = {}
	herdr._test.run = function(args, opts)
		table.insert(calls, args)
		local command = args[1] .. " " .. args[2]
		if command == "pane split" then
			opts.on_success({
				code = 0,
				stderr = "",
				stdout = vim.json.encode({
					result = { pane = { pane_id = "w7:p9" } },
				}),
			})
		elseif command == "pane process-info" then
			opts.on_success({
				code = 0,
				stderr = "",
				stdout = vim.json.encode({
					result = { process_info = { shell_pid = 17, foreground_process_group_id = 17 } },
				}),
			})
		else
			if opts.on_success then
				opts.on_success({ code = 0, stderr = "", stdout = "" })
			end
		end
	end
	local ready = false
	local session = {
		codex_real_bin = "/usr/bin/codex",
		cwd = "/tmp/project",
		herdr_agent_name = "nvim-codex-123-1",
		herdr_host_pane_id = "w7:p1",
		herdr_real_bin = "/usr/bin/herdr",
		herdr_route_path = "/tmp/route",
		herdr_wrapper_dir = "/tmp/wrapper",
	}
	herdr.create_backing_agent(session, {
		on_success = function()
			ready = true
		end,
	})
	herdr._test.run = nil

	assert_equal(session.herdr_pane_id, "w7:p9", "created pane")
	assert_equal(calls[1][1], "pane", "split first")
	assert_equal(calls[2], { "pane", "process-info", "--pane", "w7:p9" }, "wait for shell")
	assert_equal(calls[3][1], "agent", "agent third")
	assert_equal(calls[4], { "pane", "focus", "--pane", "w7:p9", "--direction", "left" }, "focus host")
	assert_equal(calls[5], { "pane", "zoom", "w7:p1", "--on" }, "zoom host")
	assert_equal(ready, true, "ready callback")
end

tests["chat launch retries while Herdr still considers the new pane busy"] = function()
	local agent_attempts = 0
	local ready = false
	local failed = false
	herdr._test.run = function(args, opts)
		local command = args[1] .. " " .. args[2]
		if command == "pane split" then
			opts.on_success({
				code = 0,
				stderr = "",
				stdout = vim.json.encode({ result = { pane = { pane_id = "w7:p10" } } }),
			})
		elseif command == "pane process-info" then
			opts.on_success({
				code = 0,
				stderr = "",
				stdout = vim.json.encode({
					result = { process_info = { shell_pid = 17, foreground_process_group_id = 17 } },
				}),
			})
		elseif command == "agent start" then
			agent_attempts = agent_attempts + 1
			if agent_attempts == 1 then
				opts.on_error({ code = 1, stderr = "", stdout = "" }, '{"error":{"code":"agent_pane_busy"}}')
			else
				opts.on_success({ code = 0, stderr = "", stdout = "" })
			end
		else
			if opts.on_success then
				opts.on_success({ code = 0, stderr = "", stdout = "" })
			end
		end
	end
	local old_defer_fn = vim.defer_fn
	vim.defer_fn = function(callback)
		callback()
	end
	herdr.create_backing_agent({
		codex_real_bin = "/usr/bin/codex",
		cwd = "/tmp/project",
		herdr_agent_name = "nvim-codex-123-busy",
		herdr_host_pane_id = "w7:p1",
		herdr_real_bin = "/usr/bin/herdr",
		herdr_route_path = "/tmp/route-busy",
		herdr_wrapper_dir = "/tmp/wrapper",
	}, {
		on_error = function()
			failed = true
		end,
		on_success = function()
			ready = true
		end,
	})
	vim.defer_fn = old_defer_fn
	herdr._test.run = nil

	assert_equal(agent_attempts, 2, "agent start attempts")
	assert_equal(ready, true, "ready callback")
	assert_equal(failed, false, "failure callback")
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

tests["reattach candidates require Neovim route state"] = function()
	local route_path = vim.fn.tempname()
	vim.fn.writefile({ "server", "1", "token" }, route_path)
	local original_route_path = herdr.route_path
	herdr.route_path = function(name)
		return name == "nvim-codex-123-2" and route_path or route_path .. ".missing"
	end
	local candidates = herdr.filter_agents({
		{ name = "nvim-codex-123-2", agent = "codex", workspace_id = "w7", pane_id = "w7:p9" },
		{ name = "reviewer", agent = "codex", workspace_id = "w7", pane_id = "w7:p2" },
	}, {})
	herdr.route_path = original_route_path
	vim.fn.delete(route_path)
	assert_equal(#candidates, 1, "candidate count")
	assert_equal(candidates[1].name, "nvim-codex-123-2", "candidate name")
end

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("codex_herdr_spec.lua: ok")
