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
			require("core.treesitter-install").run("reconcile")
		end,
		config = function()
			-- require("nvim-treesitter").install()
			vim.filetype.add({
				extension = { duckdbsql = "duckdbsql" },
				pattern = { [".*%.duckdb%.sql"] = "duckdbsql" },
			})

			-- Empty-list deep merges can retain a previous configuration on reload.
			require("tree-sitter-manager.config").cfg.ensure_installed = {}
			require("tree-sitter-manager").setup({
				languages = {
					dap_repl = {
						install_info = {
							url = "https://github.com/LiadOz/nvim-dap-repl-highlights",
							revision = "f31deba47fe3ee6ff8d2f13d9dbd06b2d1ae06b5",
							queries = "queries/dap_repl",
						},
					},
					duckdbsql = {
						install_info = {
							url = "https://github.com/Chr1sC0de/duckdbsql-grammar",
							revision = "d1a9d36268c47019e2ccb6cb4c4dfe13b5c4ceab",
							queries = "queries",
						},
					},
				},
				auto_install = false,
				-- Provision only through the serialized incremental wrapper.
				ensure_installed = {},
				nohighlight = { "dap-repl" },
			})
			require("tree-sitter-manager.config").cfg.ensure_installed = LANGUAGES
			local provision = require("core.treesitter-install")
			provision.setup_commands()
			-- Defer cold-install work until startup completes. Existing parsers are
			-- left alone; ensure never resolves remote revisions for those parsers.
			vim.schedule(function()
				local ok, err = pcall(provision.run, "ensure")
				if not ok then
					vim.notify(tostring(err), vim.log.levels.ERROR)
				end
			end)
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
