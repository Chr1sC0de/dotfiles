return {
	"jiaoshijie/undotree",
	enabled = not vim.g.vscode,
	opts = {
		-- your options
	},
	keys = {
		{ "<leader>u", "<cmd>lua require('undotree').toggle()<cr>" },
	},
}
