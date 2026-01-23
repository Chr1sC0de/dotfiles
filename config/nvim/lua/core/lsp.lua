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
	-- azure pipelines ls
	-- "azure_pipelines_ls",
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

vim.lsp.config('yamlls', {
	settings = {
		yaml = {
			format = { enable = false },
			schemas = {
				["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*",
				["https://raw.githubusercontent.com/microsoft/azure-pipelines-vscode/master/service-schema.json"] = {
					"/azure-pipeline*.y*l",
					"/*.azure*",
					"Azure-Pipelines/**/*.y*l",
					"Pipelines/*.y*l",
				},
			},
		},
	}
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
