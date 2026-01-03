vim.lsp.enable({
	-- configurations
	"tombi",
	"codebook",
	"jsonls",
	"dockerls",
	-- python
	"ty",
	"ruff",
	-- lua
	"lua_ls",
	-- markdown
	"markdown_oxide",
	-- bash
	"bashls",
	-- r
	"r_language_server",
})

local capabilities = vim.lsp.protocol.make_client_capabilities()

capabilities.workspace.didChangeWatchedFiles = {
	dynamicRegistration = true,
}

vim.lsp.config("ty", {
	settings = {
		ty = {
			diagnosticMode = "workspace",
			experimental = {
				rename = true,
			},
		},
	},
})

vim.lsp.config("jsonls", {
	cmd = { "vscode-json-language-server", "--stdio" },
	filetypes = { "json", "jsonc", "json5" },
	root_markers = { ".git" },
	settings = {
		jsonls = {
			format = { enable = true },
			validate = { enable = true },
		},
	},
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
