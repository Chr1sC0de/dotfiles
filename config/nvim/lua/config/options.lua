if not vim.g.vscode then
	vim.cmd.colorscheme("catppuccin-nvim")
end

vim.opt.number = true
vim.opt.relativenumber = true

-- vim.cmd("hi Normal guibg=NONE ctermbg=NONE")

-- Set a color for all line numbers
vim.cmd("hi LineNrAbove guifg=#888888 guibg=NONE")
vim.cmd("hi LineNr guifg=#d3e0eb guibg=NONE")
vim.cmd("hi LineNrBelow guifg=#888888 guibg=NONE")

-- disable swap files
local home = vim.loop.os_homedir()
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = home .. "/.vim/undodir"
vim.opt.undofile = true

-- incremental search
vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.scrolloff = 10
vim.opt.cmdheight = 2
vim.opt.conceallevel = 2

vim.opt.updatetime = 50
vim.opt.scrolloff = 10

vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

-- disable word wrappings

vim.o.wrap = false

-- enable exrc for workspace enabled

vim.o.exrc = true

--  allow treesitter to take priority for highlighting
vim.highlight.priorities.semantic_tokens = 95

vim.filetype.add({
	pattern = {
		["Caddyfile"] = "caddy",
		["Caddyfile.*"] = "caddy",
	},
})

-- automatically convert anything to bash if they have the bash shebang
vim.filetype.add({
	pattern = {
		[".*"] = {
			function(path, bufnr)
				local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
				if first_line and first_line:match("^#!.*bash") then
					return "bash"
				end
			end,
		},
	},
})

vim.filetype.add({
	pattern = {
		[".*/%.vscode/.*%.json"] = "jsonc",
	},
})

vim.api.nvim_create_autocmd("TermOpen", {
	desc = "Enable relative line numbers in terminal buffers",
	callback = function()
		vim.opt_local.number = true
		vim.opt_local.relativenumber = true
	end,
})
