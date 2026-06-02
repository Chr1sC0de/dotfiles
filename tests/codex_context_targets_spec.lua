vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:append(".")
package.path = table.concat({
	vim.fn.getcwd() .. "/config/nvim/lua/?.lua",
	vim.fn.getcwd() .. "/config/nvim/lua/?/init.lua",
	package.path,
}, ";")

local targets = require("codex.context.targets")

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_contains(haystack, needle, label)
	if not haystack:find(needle, 1, true) then
		error(string.format("%s: expected %q in %q", label, needle, haystack))
	end
end

local tests = {}

tests["modified file target writes snapshot when requested"] = function()
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".lua")
	vim.bo[bufnr].filetype = "lua"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local value = 42" })
	vim.bo[bufnr].modified = true

	local target = targets.build_file({ include_modified_snapshot = true })

	assert_equal(target.modified, "yes", "target modified")
	assert_equal(vim.fn.filereadable(target.snapshot_path), 1, "snapshot readable")
	assert_contains(table.concat(target.context_lines, "\n"), "Unsaved buffer snapshot:", "snapshot context")
	assert_equal(table.concat(vim.fn.readfile(target.snapshot_path), "\n"), "local value = 42", "snapshot content")

	pcall(vim.fn.delete, target.snapshot_path)
	pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end

tests["unmodified file target keeps disk read instruction"] = function()
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".lua")
	vim.bo[bufnr].filetype = "lua"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "return 1" })
	vim.bo[bufnr].modified = false

	local target = targets.build_file({ include_modified_snapshot = true })

	assert_equal(target.modified, "no", "target modified")
	assert_equal(target.snapshot_path, nil, "snapshot path")
	assert_contains(
		table.concat(target.context_lines, "\n"),
		"The file is available in the workspace.",
		"disk context"
	)

	pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("codex_context_targets_spec.lua: ok")
