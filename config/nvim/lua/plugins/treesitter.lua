local LANGUAGES = {
	"lua",
	"latex",
	"regex",
	"rust",
	"go",
	"c",
	"r",
	"bash",
	"python",
	"markdown",
	"json",
	"yaml",
	"tmux",
	"just",
	"dap_repl",
	"dockerfile",
	"toml",
	"query",
	"sql",
	"duckdbsql",
	"jinja",
	"jinja_inline",
	"caddy",
	"mermaid",
	"just",
}
---@module "lazy"
---@type LazySpec
return {
	{
		"nvim-treesitter/nvim-treesitter",
		enabled = not vim.g.vscode,
		dependencies = {
			{
				"romus204/tree-sitter-manager.nvim",
				branch = "develop",
			},
			{
				"LiadOz/nvim-dap-repl-highlights",
				config = function()
					require("nvim-dap-repl-highlights").setup()
				end,
			},
			{
				"nvim-treesitter/nvim-treesitter-context",
				opts = {
					max_lines = 4,
					multiline_threshold = 2,
				},
			},
		},
		lazy = false,
		branch = "main",
		build = function(plugin)
			-- Load the config explicitly: Lazy does not load plugins for function build hooks.
			require("lazy.core.loader").load(plugin, { task = "build" })
			-- Avoid TSUpdate/TSUpdateSync collisions with the other Treesitter plugins.
			local util = require("tree-sitter-manager.util")
			local installer = require("tree-sitter-manager.installer")
			local installed = vim.iter(LANGUAGES):filter(util.is_installed):totable()
			installer.update(installed)
		end,
		config = function()
			-- require("nvim-treesitter").install()
			vim.filetype.add({
				extension = { duckdbsql = "duckdbsql" },
				pattern = { [".*%.duckdb%.sql"] = "duckdbsql" },
			})

			require("tree-sitter-manager").setup({
				languages = {
					dap_repl = {
						install_info = {
							url = "https://github.com/LiadOz/nvim-dap-repl-highlights",
							queries = "queries/dap_repl",
						},
					},
					duckdbsql = {
						install_info = {
							url = "https://github.com/Chr1sC0de/duckdbsql-grammar",
							queries = "queries",
						},
					},
				},
				auto_install = true,
				ensure_installed = LANGUAGES,
				nohighlight = { "dap-repl" },
			})
		end,
	},
	{
		"MeanderingProgrammer/treesitter-modules.nvim",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		---@module 'treesitter-modules'
		---@type ts.mod.UserConfig
		opts = {
			incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "<A-o>",
					node_incremental = "<A-o>",
					scope_incremental = "<A-O>",
					node_decremental = "<A-i>",
				},
			},
		},
	},
}
