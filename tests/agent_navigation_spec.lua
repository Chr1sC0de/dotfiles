vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local herdr = require("workmux.herdr")
local function equal(actual, expected)
	assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. " != " .. vim.inspect(expected))
end
local calls, picker, preview_pane = {}, nil, nil
local agent = {
	name = "reviewer",
	agent = "codex",
	pane_id = "w2:p2",
	tab_id = "w2:t1",
	workspace_id = "w2",
	tokens = { "nvim_host_pane=w2:p1" },
}
local snapshot = { agents = { agent }, panes = { { pane_id = "w2:p1", tab_id = "w2:t1" } }, tabs = {}, workspaces = {} }
_G.Snacks = { picker = {
	pick = function(opts)
		picker = opts
	end,
} }
package.loaded["snacks.picker.preview"] = {
	cmd = function(args)
		preview_pane = args[2]
	end,
}
herdr._test.run = function(args, opts)
	table.insert(calls, args)
	local result = args[1] == "api" and { snapshot = snapshot } or { agent = agent }
	if opts.on_success then
		opts.on_success({ code = 0, stdout = vim.json.encode({ result = result }) })
	end
end
herdr.select_workspace()
picker.preview({
	item = picker.items[1],
	win = vim.api.nvim_get_current_win(),
	preview = {
		reset = function() end,
		minimal = function() end,
		wo = function() end,
		set_title = function() end,
	},
})
equal(preview_pane, "w2:p2")
-- The agent moves after opening the picker. Navigation must use fresh identity.
agent = vim.tbl_extend("force", agent, { pane_id = "w3:p4", tab_id = "w3:t2", workspace_id = "w3" })
calls = {}
picker.confirm({ close = function() end }, picker.items[1])
equal(calls, {
	{ "agent", "get", "reviewer" },
	{ "workspace", "focus", "w3" },
	{ "tab", "focus", "w3:t2" },
	{ "agent", "focus", "reviewer" },
	{ "pane", "zoom", "w3:p4", "--on" },
})
-- A vanished agent must not navigate using stale pane metadata.
calls = {}
vim.notify = function() end
herdr._test.run = function(args, opts)
	table.insert(calls, args)
	opts.on_error({ code = 1 }, "agent disappeared")
end
picker.confirm({ close = function() end }, picker.items[1])
equal(calls, { { "agent", "get", "reviewer" } })
calls = {}
herdr._test.run = function(args, opts)
	table.insert(calls, args)
	if args[1] == "tab" then
		opts.on_error({ code = 1 }, "tab disappeared")
	elseif opts.on_success then
		opts.on_success({ stdout = vim.json.encode({ result = { agent = agent } }) })
	end
end
picker.confirm({ close = function() end }, picker.items[1])
equal(calls, { { "agent", "get", "reviewer" }, { "workspace", "focus", "w3" }, { "tab", "focus", "w3:t2" } })
-- Agents discovered outside Neovim can have JSON-null names and directories.
herdr._test.run = function(_, opts)
	opts.on_success({
		code = 0,
		stdout = vim.json.encode({
			result = {
				snapshot = {
					agents = {
						{ name = vim.NIL, pane_id = "w4:p1", cwd = vim.NIL, foreground_cwd = vim.NIL, agent = "codex" },
					},
					panes = {},
					tabs = {},
					workspaces = {},
				},
			},
		}),
	})
end
local unnamed
herdr.agent_snapshot(function(items)
	unnamed = items[1]
end)
equal(unnamed.name, "w4:p1")
equal(unnamed.agent_cwd, "")
print("agent_navigation_spec.lua: ok")
