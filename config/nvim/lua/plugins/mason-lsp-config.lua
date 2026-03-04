return {
	"mason-org/mason-lspconfig.nvim",
	enabled = not vim.g.vscode,
	dependencies = {
		{ "mason-org/mason.nvim", opts = {} },
		"neovim/nvim-lspconfig",
	},
}
