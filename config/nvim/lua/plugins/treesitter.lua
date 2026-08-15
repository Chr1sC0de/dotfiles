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
				"nvim-treesitter/nvim-treesitter-context",
				opts = {
					max_lines = 4,
					multiline_threshold = 2,
				},
			},
		},
		lazy = false,
		branch = "main",
		build = ":TSUpdate",
		config = function()
			local languages = {
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
				"dap_repl",
				"dockerfile",
				"toml",
				"query",
				"sql",
				"duckdb",
				"jinja",
				"jinja_inline",
				"caddy",
				"mermaid",
			}
			-- require("nvim-treesitter").install()
			vim.filetype.add({
				extension = { duckdb = "duckdb" },
				pattern = { [".*%.duckdb%.sql"] = "duckdb" },
			})

			require("tree-sitter-manager").setup({
				languages = {
					dap_repl = {
						install_info = {
							url = "https://github.com/LiadOz/nvim-dap-repl-highlights",
							queries = "queries/dap_repl",
						},
					},
					duckdb = {
						install_info = {
							url = "/home/cmamon/GitHub/duckdb-grammar",
							queries = "queries",
						},
					},
				},
				auto_install = true,
				ensure_installed = languages,
			})
			vim.api.nvim_create_autocmd("FileType", {
				pattern = languages,
				callback = function(args)
					vim.treesitter.start(args.buf)
				end,
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
