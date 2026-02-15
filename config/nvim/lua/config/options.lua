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

-- disable word wrappings

vim.o.wrap = false

-- enable exrc for workspace enabled

vim.o.exrc = true

--  allow treesitter to take priority for highlighting
vim.highlight.priorities.semantic_tokens = 95

vim.filetype.add({
	pattern = {
		[".*/Caddyfile"] = "caddy",
	},
})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
	pattern = "Caddyfile",
	callback = function(args)
		vim.bo[args.buf].filetype = "caddy"
		vim.treesitter.start(args.buf, "caddy")
	end,
})
