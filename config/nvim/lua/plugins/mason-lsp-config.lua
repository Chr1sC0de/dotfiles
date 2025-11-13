return {
	"mason-org/mason-lspconfig.nvim",
	opts = {
		ensure_installed = {
			-- configurations
			"tombi",
			"codebook",
			"jsonls",
			"dockerls",
			-- python
			"basedpyright",
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
