vim.api.nvim_create_autocmd("FileType", {
	pattern = { "y*ml" },
	callback = function()
		vim.treesitter.start()
	end,
})
