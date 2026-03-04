return {
	"jay-babu/mason-nvim-dap.nvim",
	enabled = not vim.g.vscode,
	dependencies = "mason.nvim",
	cmd = { "DapInstall", "DapUninstall" },
	lazy = false,
	opts = {
		ensure_installed = {},
		automatic_installation = false,
		handlers = {},
	},
}
