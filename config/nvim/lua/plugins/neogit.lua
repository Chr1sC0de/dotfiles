return {
	"NeogitOrg/neogit",
	lazy = true,
	enabled = not vim.g.vscode,
	dependencies = {
		"nvim-lua/plenary.nvim",
		"sindrets/diffview.nvim",
	},
	opts = {
		integrations = {
			snacks = true,
			telescope = false,
		},
	},
	cmd = "Neogit",
	keys = {
		{ "<leader>gg", "<cmd>Neogit<cr>", desc = "Show Neogit UI" },
	},
}
