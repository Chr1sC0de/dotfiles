vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local herdr = require("opencode.herdr")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
herdr.route_path = function(name)
	return root .. "/" .. name .. ".route"
end
local agent = { name = "nvim-opencode-td-test", pane_id = "w1:p2", cwd = "/project" }
local session = {
	herdr_agent_name = agent.name,
	herdr_pane_id = agent.pane_id,
	cwd = agent.cwd,
	herdr_route_path = herdr.route_path(agent.name),
	tandem_env = { OPENCODE_CONFIG_CONTENT = "{}" },
	tandem_root = "/project",
}
assert(herdr.launch_metadata(agent) == nil)
assert(herdr.write_launch_metadata(session))
assert(herdr.launch_metadata(agent).tandem_root == "/project")
assert(herdr.launch_metadata(vim.tbl_extend("force", agent, { pane_id = "w2:p1" })) == nil)
assert(herdr.launch_metadata(vim.tbl_extend("force", agent, { cwd = "/other" })) == nil)
assert(herdr.launch_metadata({ name = "../invalid", pane_id = agent.pane_id }) == nil)
local path = session.herdr_route_path .. ".launch.json"
vim.fn.writefile({ "invalid" }, path)
assert(herdr.launch_metadata(agent) == nil)
assert(herdr.write_launch_metadata(session))
vim.fn.writefile({ "server", "id", "token" }, session.herdr_route_path)
herdr.remove_route(session)
assert(vim.fn.filereadable(path) == 0)
assert(vim.fn.filereadable(session.herdr_route_path) == 0)
herdr._test.run = function(args, opts)
	assert(args[3] == "w4:p1")
	opts.on_success({ stdout = '{"result":{"agent":{"name":null,"cwd":null,"pane_id":"w4:p1","agent":"opencode"}}}' })
end
local unnamed
herdr.get_agent("w4:p1", function(value)
	unnamed = value
end)
assert(unnamed.name == nil and unnamed.cwd == nil)
assert(#herdr.filter_agents({ unnamed }) == 0)
vim.fn.delete(root, "rf")
print("opencode_agent_metadata_spec.lua: ok")
