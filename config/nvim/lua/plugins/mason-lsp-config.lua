return {
	"mason-org/mason-lspconfig.nvim",
	opts = {
		ensure_installed = {
			-- configurations
			"tombi",
			"codebook",
			"jsonls",
			"docker_language_server",
			-- python
			"ty",
			"ruff",
			-- lua
			"lua_ls",
			-- markdown
			"markdown_oxide",
			-- bash
			"bashls",
		},
	},
	dependencies = {
		{ "mason-org/mason.nvim", opts = {} },
		"neovim/nvim-lspconfig",
	},
}
