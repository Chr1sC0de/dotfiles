---@module "lazy"
---@type LazySpec
return {
	"nvim-treesitter/nvim-treesitter",
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
		require("nvim-treesitter").install({
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
		})
	end,
}
