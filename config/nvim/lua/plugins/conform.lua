return {
	"stevearc/conform.nvim",
	opts = {},
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		require("conform").setup({
			formatters_by_ft = {
				python = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
				sh = { "shfmt", "shellcheck" },
				bash = { "shfmt", "shellcheck" },
				containerfile = { "dockerfmt" },
				dockerfile = { "dockerfmt" },
				markdown = { "cbfmt", "mdformat" },
				lua = { "stylua" },
				json = { "fixjson" },
				toml = { "pyproject-fmt" },
			},
			format_on_save = {
				lsp_fallback = true,
				async = false,
				timeout_ms = 1000,
			},
		})
		vim.keymap.set({ "n", "v" }, "<leader>mp", function()
			require("conform").format({
				lsp_fallback = true,
				async = false,
				timeout_ms = 1000,
			})
		end, { desc = "conform: Format file or range (in visual mode)" })

		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = "*",
			callback = function(args)
				require("conform").format({ bufnr = args.buf })
			end,
		})
	end,
}
