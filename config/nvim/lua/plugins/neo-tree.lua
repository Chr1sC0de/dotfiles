return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	enabled = not vim.g.vscode,
	dependencies = {
		"nvim-lua/plenary.nvim",
		"MunifTanjim/nui.nvim",
		"nvim-tree/nvim-web-devicons", -- optional, but recommended
	},
	lazy = false, -- neo-tree will lazily load itself
	config = function()
		require("neo-tree").setup({
			filesystem = {
				hijack_netrw_behavior = "disabled",
				window = {
					mappings = {
						["Z"] = "expand_all_subnodes",
						["z"] = "close_all_subnodes",
					},
				},
			},
		})
	end,
}
