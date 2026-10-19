-- Run from the repository root with: nvim --headless -u NONE -i NONE -n -l config/nvim/tests/treesitter_build_test.lua
local base = vim.fn.stdpath("data") .. "/lazy/"
for _, plugin in ipairs({ "lazy.nvim", "nvim-treesitter", "tree-sitter-manager.nvim", "treesitter-modules.nvim" }) do
	vim.opt.runtimepath:prepend(base .. plugin)
end

-- Keep real command registration, but prevent filesystem and parser installation side effects.
vim.fn.mkdir = function()
	return 1
end
vim.system = function()
	error("Unexpected external command")
end
vim.fn.jobstart = function()
	error("Unexpected external command")
end
vim.notify = function(message, level)
	assert(level ~= vim.log.levels.ERROR, message)
end
package.loaded["nvim-treesitter.install"] = {
	update = function()
		error("Build must use tree-sitter-manager, not the native installer")
	end,
}
local updates, waits = {}, {}
package.loaded["tree-sitter-manager.installer"] = {
	setup = function() end,
	install = function() end,
	update = function(languages)
		table.insert(updates, vim.deepcopy(languages))
	end,
	wait = function(languages)
		assert(vim.deep_equal(updates[#updates], languages), "Wait must follow update for the same parsers")
		table.insert(waits, vim.deepcopy(languages))
		return true
	end,
}
package.loaded["tree-sitter-manager.ui"] = {
	setup = function() end,
	open = function() end,
	render = function() end,
}
local installed = { lua = true, dap_repl = true, duckdbsql = true }
require("tree-sitter-manager.util").is_installed = function(language)
	return installed[language] == true
end

local spec = dofile("config/nvim/lua/plugins/treesitter.lua")[1]
local commands = require("treesitter-modules.core.command")
dofile(base .. "nvim-treesitter/plugin/nvim-treesitter.lua")
spec.config()
commands.init()

-- Reproduce the reported failure with the actual conflicting command definitions.
assert(not vim.api.nvim_get_commands({}).TSUpdateSync.bang)
local ok, err = pcall(vim.api.nvim_parse_cmd, "TSUpdateSync!", {})
assert(not ok and err:find("E477: No ! allowed", 1, true), "Old build hook must reproduce E477")
assert(type(spec.build) == "function", "Build must bypass shared Ex command names")

local load_count = 0
local cold = false
require("lazy.core.loader").load = function(plugin, reason)
	assert(plugin == spec and reason.task == "build")
	load_count = load_count + 1
	if cold then
		spec.config()
		commands.init()
		cold = false
	end
end
local task = {
	plugin = spec,
	log = function() end,
}
local build = require("lazy.manage.task.plugin").build.run
local function check(expected)
	local previous_loads = load_count
	build(task)
	assert(load_count == previous_loads + 1, "Function build hook must explicitly load its plugin")
	assert(vim.deep_equal(updates[#updates], expected), "Update must select only installed parsers")
	assert(vim.deep_equal(waits[#waits], expected), "Build must wait for selected parsers")
	assert(#updates == #waits)
end

local expected = { "dap_repl", "duckdbsql", "lua" }
check(expected) -- modules owns TSUpdateSync
spec.config()
check(expected) -- manager owns TSUpdateSync
installed = {}
check({}) -- no parsers installed
installed = { lua = true, dap_repl = true, duckdbsql = true }
require("tree-sitter-manager.config").languages = {}
cold = true
check(expected) -- load must configure custom languages before selecting installed parsers

print("treesitter_build_test.lua: ok (collision reproduced; both load orders, empty set, and cold load passed)")
