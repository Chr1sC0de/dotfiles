vim.api.nvim_create_autocmd("FileType", {
	pattern = { "toml" },
	callback = function()
		vim.treesitter.start()
	end,
})
