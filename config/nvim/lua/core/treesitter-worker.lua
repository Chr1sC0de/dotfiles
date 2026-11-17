-- Invoked with -u NONE -l: never loads the user's init or launches more workers.
local request_path = assert(arg[1], "Missing Tree-sitter worker request")
local request = vim.json.decode(table.concat(vim.fn.readfile(request_path), "\n"))
vim.fn.delete(request_path)
local function log(message)
	vim.fn.writefile(vim.split(tostring(message), "\n"), request.log, "a")
end
vim.notify = log
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	log(table.concat(parts, " "))
end
local ok, err = xpcall(function()
	vim.opt.runtimepath = request.runtimepath
	local config = vim.deepcopy(request.config)
	config.ensure_installed, config.auto_install = {}, false
	require("tree-sitter-manager").setup(config)
	local state = require("tree-sitter-manager.config")
	state.effective_repos = request.repos
	state.cfg.ensure_installed = request.config.ensure_installed
	log("Tree-sitter worker: " .. request.mode)
	local summary = require("core.treesitter-install").run(request.mode, request.selected)
	log(
		"Complete: "
			.. #summary.built
			.. " built, "
			.. #summary.queries
			.. " query refreshes, "
			.. #summary.skipped
			.. " skipped"
	)
end, debug.traceback)
if not ok then
	log(err)
	vim.cmd("cquit 1")
end
vim.cmd("qa!")
