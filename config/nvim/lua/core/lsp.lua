-- blink capabilities
local capabilities = require("blink.cmp").get_lsp_capabilities({
	textDocument = {
		foldingRange = {
			dynamicRegistration = false,
			lineFoldingOnly = true,
		},
	},
})

-- global defaults
vim.lsp.config("*", {
	capabilities = capabilities,
	root_markers = { ".git" },
})

-- python

-- Optional: Only required if you need to update the language server settings

vim.lsp.config("ty", {
	settings = {
		ty = {
			diagnosticMode = "workspace",
		},
	},
})

vim.lsp.config("zuban", {
	name = "zuban",
	cmd = { "zuban", "server" },
	root_markers = { "pyproject.toml", ".git" },
	filetypes = { "python" },
})

vim.lsp.config("ruff", {
	filetypes = { "python" },
})

-- json
vim.lsp.config("jsonls", {
	cmd = { "vscode-json-language-server", "--stdio" },
	filetypes = { "json", "jsonc", "json5" },
	settings = {
		json = {
			format = { enable = true },
			schemas = require("schemastore").json.schemas(),
			validate = { enable = true },
		},
	},
})

-- yaml
vim.lsp.config("yamlls", {
	settings = {
		yaml = {
			format = { enable = false },
			schemaStore = {
				enable = false,
				url = "",
			},
			schemas = require("schemastore").yaml.schemas(),
		},
	},
})

-- diagnostics
vim.diagnostic.config({
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

-- enable servers
vim.lsp.enable({
	-- configs
	"taplo",
	"codebook",
	"jsonls",
	"dockerls",
	"yamlls",

	-- python
	"ty",
	"ruff",

	-- lua
	"lua_ls",
	"markdown",
	"markdown_oxide",

	-- bash
	"bashls",

	-- r
	"r_language_server",

	-- treesitter
	"ts_query_ls",
})
