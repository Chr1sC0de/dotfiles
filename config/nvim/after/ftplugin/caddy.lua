vim.api.nvim_create_autocmd("FileType", {
	pattern = { "caddy" },
	callback = function()
		vim.treesitter.start()
	end,
})
