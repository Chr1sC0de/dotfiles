-- Standalone child process: never validate a replacement library from Neovim's
-- cache of previously loaded parsers.
local ok, err = xpcall(function()
	local language, path = arg[1], arg[2]
	vim.opt.runtimepath = vim.json.decode(arg[3])
	assert(vim.treesitter.language.add(language, { path = path }))
	local parser_only = arg[4] == "parser"
	local opts = parser_only and { injections = { [language] = "" } } or nil
	local parser = vim.treesitter.get_string_parser("", language, opts)
	assert(parser:parse()[1], "Parser produced no tree")
	if not parser_only then
		for _, kind in ipairs({ "highlights", "injections", "locals", "folds", "indents" }) do
			vim.treesitter.query.get(language, kind)
		end
	end
end, debug.traceback)
if not ok then
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd("cquit 1")
end
