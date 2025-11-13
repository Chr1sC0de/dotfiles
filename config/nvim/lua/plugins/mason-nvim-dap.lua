return {
	"jay-babu/mason-nvim-dap.nvim",
	dependencies = "mason.nvim",
	cmd = { "DapInstall", "DapUninstall" },
	ensure_installed = { "python", "bash" },
	automatic_installation = true,
	opts = {
		automatic_installation = true,
		handlers = {},
		ensure_installed = {},
	},
	config = function() end,
}
