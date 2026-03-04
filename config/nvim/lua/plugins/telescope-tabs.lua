return {
	"LukasPietzschmann/telescope-tabs",
	enabled = not vim.g.vscode,
	config = function()
		require("telescope").load_extension("telescope-tabs")
		require("telescope-tabs").setup({})

		vim.keymap.set("n", "<leader>ft", function()
			require("telescope-tabs").list_tabs()
		end, { desc = "Telescope: tabs" })
	end,

	dependencies = { "nvim-telescope/telescope.nvim" },
}
