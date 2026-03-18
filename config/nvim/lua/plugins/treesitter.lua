---@module "lazy"
---@type LazySpec
return {
	{
		"nvim-treesitter/nvim-treesitter",
		enabled = not vim.g.vscode,
		dependencies = {
			{
				"nvim-treesitter/nvim-treesitter-context",
				"LiadOz/nvim-dap-repl-highlights",
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
			require("nvim-dap-repl-highlights").setup()
			local languages = {
				"lua",
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
				"jinja",
				"jinja_inline",
				"caddy",
			}
			require("nvim-treesitter").install()
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
