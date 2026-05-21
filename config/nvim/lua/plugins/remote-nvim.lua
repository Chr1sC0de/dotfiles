return {
	"amitds1997/remote-nvim.nvim",
	enabled = not vim.g.vscode,
	version = "*", -- Pin to GitHub releases
	dependencies = {
		"nvim-lua/plenary.nvim", -- For standard functions
		"MunifTanjim/nui.nvim", -- To build the plugin UI
	},
	specs = {
		{ "nvim-telescope/telescope.nvim", enabled = false },
	},
	config = function()
		require("remote-nvim").setup({})
		require("config.snacks_pickers").setup_remote_start()
	end,
}
