vim.lsp.enable({
	"tombi",
	"codebook",
	"basedpyright",
	"bashls",
	"json_lsp",
	"lua_ls",
	"markdown_oxide",
	"ruff",
})

local capabilities = vim.lsp.protocol.make_client_capabilities()

-- enable dynamic registration for watched files
capabilities.workspace.didChangeWatchedFiles = {
	dynamicRegistration = true,
}

vim.lsp.config("tombi", {
	filetypes = { "toml" },
})

vim.lsp.config("basedpyright", {
	capabilities = capabilities,
	filetypes = { "python" },
})

vim.diagnostic.config({
	-- virtual_lines = true,
	-- virtual_text = true,
	underline = true,
	update_in_insert = false,
	severity_sort = true,
	float = {
		border = "rounded",
		source = true,
	},
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = "󰅚 ",
			[vim.diagnostic.severity.WARN] = "󰀪 ",
			[vim.diagnostic.severity.INFO] = "󰋽 ",
			[vim.diagnostic.severity.HINT] = "󰌶 ",
		},
		numhl = {
			[vim.diagnostic.severity.ERROR] = "ErrorMsg",
			[vim.diagnostic.severity.WARN] = "WarningMsg",
		},
	},
})
