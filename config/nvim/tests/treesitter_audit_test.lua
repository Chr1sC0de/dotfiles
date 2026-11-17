-- Run: nvim --headless -u NONE -i NONE -n -l config/nvim/tests/treesitter_audit_test.lua
local case = "ok"
package.loaded["core.treesitter-install"] = {
	languages = function()
		return { "lua" }
	end,
	finish = function()
		assert(case ~= "missing", "fixture missing parser")
	end,
}
vim.treesitter.language.add = function()
	return case ~= "unloadable"
end
vim.treesitter.get_parser = function()
	return {
		parse = function()
			return {
				{
					root = function()
						return {
							has_error = function()
								return case == "parse-error"
							end,
						}
					end,
				},
			}
		end,
	}
end
vim.treesitter.query.get = function()
	assert(case ~= "query-error", "fixture incompatible query")
end
for _, scenario in ipairs({ "ok", "missing", "unloadable", "parse-error", "query-error" }) do
	case = scenario
	local ok, err = pcall(dofile, "tests/nvim_treesitter_audit.lua")
	assert(ok == (case == "ok"), case .. ": " .. tostring(err))
	-- Failed checks may leave a scratch buffer behind; avoid fixture name clashes.
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(buffer):find("dotfiles-parser-audit-", 1, true) then
			vim.api.nvim_buf_delete(buffer, { force = true })
		end
	end
end
print("treesitter_audit_test.lua: ok (success, missing, unloadable, parse error, incompatible queries)")
