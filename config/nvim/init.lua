require("core.lazy")

if not vim.g.vscode then
	require("core.lsp")
	require("config.autocmds")
end

require("config.options")
require("config.keymaps")

local border_colors = "#7aa7f5"

-- Transparent floating window backgrounds
vim.api.nvim_set_hl(0, "NormalFloat", { fg = border_colors, bg = "none" })
vim.api.nvim_set_hl(0, "FloatBorder", { fg = border_colors, bg = "none" })

-- Optional: if your theme also uses FloatTitle or FloatFooter
vim.api.nvim_set_hl(0, "FloatTitle", { fg = border_colors, bg = "none" })
vim.api.nvim_set_hl(0, "FloatFooter", { fg = border_colors, bg = "none" })

vim.opt.signcolumn = "yes"

vim.env.IN_NEOVIM_TERMINAL = true

if vim.env.TMUX then
	vim.g.clipboard = "osc52"
end

-- set flags and shell

-- Normalize shell name from a full path or just the name
local function normalize_shell(shell_path)
	-- get the basename if it's a path
	local name = shell_path:match("^.+[\\/]([^\\/]+)$") or shell_path
	-- remove optional ".exe" on Windows
	name = name:gsub("%.exe$", "")
	-- lowercase for comparison
	return name:lower()
end

local shell = vim.g.SHELL or vim.o.shell
local sh = normalize_shell(shell)

if sh == "cmd" then
	vim.opt.shell = shell
	vim.opt.shellcmdflag = "/c"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
elseif sh == "pwsh" then
	vim.opt.shell = shell
	vim.opt.shellcmdflag = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command"
	vim.opt.shellredir = "2>&1 | Out-File -Encoding utf8 %s"
	vim.opt.shellpipe = "2>&1 | Out-File -Encoding utf8 %s"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
elseif sh == "bash" then
	vim.opt.shell = shell
	vim.opt.shellcmdflag = "-c"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
else
	vim.opt.shell = shell
	vim.opt.shellcmdflag = "-c"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
end
