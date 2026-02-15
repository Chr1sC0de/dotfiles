return {
	"stevearc/conform.nvim",
	opts = {},
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		require("conform").setup({
			formatters_by_ft = {
				python = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
				make = { "bake" },
				sh = { "shfmt", "shellcheck" },
				bash = { "shfmt", "shellcheck" },
				containerfile = { "dockerfmt" },
				dockerfile = { "dockerfmt" },
				-- markdown = { "cbfmt", "mdformat" },
				lua = { "stylua" },
				json = { "fixjson" },
				yaml = { "yamlfmt" },
				toml = function(bufnr)
					if vim.api.nvim_buf_get_name(bufnr):match("pyproject%.toml$") then
						return { "pyproject-fmt" }
					end
					-- Return another formatter for standard .toml files, or nil
					return {}
				end,
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
