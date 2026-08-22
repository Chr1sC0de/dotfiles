local data_dir = vim.fn.stdpath("data")

vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:prepend(data_dir .. "/site")
vim.opt.runtimepath:prepend(data_dir .. "/lazy/nvim-treesitter")
vim.opt.runtimepath:prepend(data_dir .. "/lazy/nvim-dap-repl-highlights")

local specs = dofile(vim.fn.getcwd() .. "/config/nvim/lua/plugins/treesitter.lua")
local treesitter_spec = specs[1]
local repl_highlights_spec

for _, dependency in ipairs(treesitter_spec.dependencies) do
	if type(dependency) == "table" and dependency[1] == "LiadOz/nvim-dap-repl-highlights" then
		repl_highlights_spec = dependency
		break
	end
end

assert(repl_highlights_spec, "Treesitter should depend on nvim-dap-repl-highlights")
assert(type(repl_highlights_spec.config) == "function", "REPL highlights dependency should configure itself")

local manager_options
package.loaded["tree-sitter-manager"] = {
	setup = function(options)
		manager_options = options
	end,
}

repl_highlights_spec.config()
treesitter_spec.config()

assert(
	vim.list_contains(manager_options.nohighlight, "dap-repl"),
	"tree-sitter-manager should leave dap-repl highlighting to nvim-dap-repl-highlights"
)

package.loaded.dap = {
	listeners = { after = { event_initialized = {} } },
	session = function()
		return { config = {}, filetype = "python" }
	end,
}

vim.cmd("filetype plugin on")

local repl_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(repl_buffer)
vim.api.nvim_buf_set_lines(repl_buffer, 0, -1, false, { "dap>print(1)", "1", "" })
vim.bo[repl_buffer].filetype = "dap-repl"

local highlighter = vim.treesitter.highlighter.active[repl_buffer]
assert(highlighter, "DAP REPL buffer should have an active Treesitter highlighter")

highlighter.tree:parse(true)
assert(highlighter.tree:lang() == "dap_repl", "DAP REPL should use the dap_repl root parser")
assert(highlighter.tree:children().python, "DAP REPL should inject the session's Python parser")

print("dap_repl_highlights_test.lua: ok")
