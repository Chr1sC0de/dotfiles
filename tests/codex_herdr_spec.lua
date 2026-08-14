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

tests["reattach candidates are scoped and require route state"] = function()
	local route_path = vim.fn.tempname()
	vim.fn.writefile({ "server", "1", "token" }, route_path)

	local original_route_path = herdr.route_path
	herdr.route_path = function(name)
		if name == "nvim-codex-123-2" then
			return route_path
		end
		return route_path .. ".missing"
	end

	local candidates = herdr.filter_agents({
		{ name = "nvim-codex-123-2", agent = "codex", workspace_id = "w7", pane_id = "w7:p9" },
		{ name = "nvim-codex-123-3", agent = "codex", workspace_id = "w8", pane_id = "w8:p1" },
		{ name = "reviewer", agent = "codex", workspace_id = "w7", pane_id = "w7:p2" },
	}, "w7", {})

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
