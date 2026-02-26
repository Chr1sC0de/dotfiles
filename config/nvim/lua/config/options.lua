vim.cmd.colorscheme("catppuccin")

vim.o.shell = os.getenv("SHELL") or vim.fn.exepath("bash")

vim.opt.number = true
vim.opt.relativenumber = true

-- vim.cmd("hi Normal guibg=NONE ctermbg=NONE")

-- Set a color for all line numbers
vim.cmd("hi LineNrAbove guifg=#888888 guibg=NONE")
vim.cmd("hi LineNr guifg=#d3e0eb guibg=NONE")
vim.cmd("hi LineNrBelow guifg=#888888 guibg=NONE")

-- disable swap files
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
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
