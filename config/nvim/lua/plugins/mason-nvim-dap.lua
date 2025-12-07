return {
	"jay-babu/mason-nvim-dap.nvim",
	dependencies = "mason.nvim",
	lazy = false,
	cmd = { "DapInstall", "DapUninstall" },
	ensure_installed = { "debugpy", "bash-debug-adapter" },
	automatic_installation = true,
	opts = {
		automatic_installation = true,
		handlers = {},
		ensure_installed = {},
	},
	config = function() end,
}
