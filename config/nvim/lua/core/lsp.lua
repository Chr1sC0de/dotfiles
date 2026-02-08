vim.lsp.enable({
	-- configurations
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
			schemas = require("schemastore").json.schemas(),
			validate = { enable = true },
		},
	},
})

vim.lsp.config("yamlls", {
	settings = {
		yaml = {
			format = { enable = false },
			schemaStore = {
				-- You must disable built-in schemaStore support if you want to use
				-- this plugin and its advanced options like `ignore`.
				enable = false,
				-- Avoid TypeError: Cannot read properties of undefined (reading 'length')
				url = "",
			},
			schemas = require("schemastore").yaml.schemas(),
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
