local M = {}

function M.args(cwd, read_only, path)
	local ok, tandem = pcall(require, "tandem")
	if not ok or type(tandem.codex_args) ~= "function" then
		return nil, "Install tandem.nvim and its pinned CLI before launching Codex from Neovim."
	end
	return tandem.codex_args({ cwd = cwd, read_only = read_only, path = path })
end

return M
