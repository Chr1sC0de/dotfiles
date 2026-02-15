vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "caddy" },
	callback = function()
		vim.treesitter.start()
	end,
})
