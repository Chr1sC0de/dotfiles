return {
	"nvim-treesitter/nvim-treesitter",
	brach = "master",
	build = ":TSUpdate",
	dependencies = {
		"windwp/nvim-ts-autotag",
		"LiadOz/nvim-dap-repl-highlights",
	},
	lazy = vim.fn.argc(-1) == 0, -- load treesitter early when opening a file from the cmdline,
	init = function(plugin)
		-- PERF: add nvim-treesitter queries to the rtp and it's custom query predicates early
		-- This is needed because a bunch of plugins no longer `require("nvim-treesitter")`, which
		-- no longer trigger the **nvim-treesitter** module to be loaded in time.
		-- Luckily, the only things that those plugins need are the custom queries, which we make available
		-- during startup.
		require("lazy.core.loader").add_to_rtp(plugin)
		require("nvim-treesitter.query_predicates")
	end,
	keys = {
		{ "<c-space>", desc = "Treesitter: Increment Selection" },
		{ "<bs>", desc = "Treesitter: Decrement Selection", mode = "x" },
	},
	config = function()
		require("nvim-treesitter.configs").setup({
			-- A list of parser names, or "all"
			ensure_installed = {
				"vimdoc",
				"javascript",
				"typescript",
				"c",
				"lua",
				"rust",
				"python",
				"jsdoc",
				"bash",
				"json",
				"html",
				"css",
				"dap_repl",
				"tsx",
			},
			sync_install = true,
			auto_install = true,
			autotag = { enable = true },
			indent = {
				enable = true,
			},
			incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "<C-space>",
					node_incremental = "<C-space>",
					scope_incremental = false,
					node_decremental = "<bs>",
				},
			},
			fold = {
				enable = true,
			},
			highlight = {
				enable = true,
				additional_vim_regex_highlighting = { "markdown" },
			},
		})

		local treesitter_parser_config = require("nvim-treesitter.parsers").get_parser_configs()
		treesitter_parser_config.templ = {
			install_info = {
				url = "https://github.com/vrischmann/tree-sitter-templ.git",
				files = { "src/parser.c", "src/scanner.c" },
				branch = "master",
			},
		}

		vim.treesitter.language.register("templ", "templ")
	end,
}
