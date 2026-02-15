vim.opt.expandtab = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 0

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "makefile", "make" },
	callback = function()
		vim.treesitter.start()
	end,
})
