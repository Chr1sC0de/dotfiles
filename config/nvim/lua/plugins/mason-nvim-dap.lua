return {
	"jay-babu/mason-nvim-dap.nvim",
	dependencies = "mason.nvim",
	cmd = { "DapInstall", "DapUninstall" },
	lazy = false,
	opts = {
		ensure_installed = {},
		automatic_installation = false,
		handlers = {},
	},
}
