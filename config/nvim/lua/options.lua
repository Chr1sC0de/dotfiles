vim.cmd.colorscheme "catppuccin"

vim.opt.number = true
vim.opt.relativenumber = true

-- vim.cmd("hi Normal guibg=NONE ctermbg=NONE")

-- Set a color for all line numbers
vim.cmd("hi LineNrAbove guifg=#888888 guibg=NONE")
vim.cmd("hi LineNr guifg=#d3e0eb guibg=NONE")
vim.cmd("hi LineNrBelow guifg=#888888 guibg=NONE")

-- spaces instead of tabs with 4 spaces for the shift width
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

-- disable swap files
vim.opt.swapfile = false

-- incremental search
vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.scrolloff = 10
vim.opt.cmdheight = 2
vim.opt.conceallevel = 2

vim.opt.scrolloff = 8
