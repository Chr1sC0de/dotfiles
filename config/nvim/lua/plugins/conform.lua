return {
	"stevearc/conform.nvim",
	opts = {},
	event = { "BufReadPre", "BufNewFile" },
	enabled = not vim.g.vscode,
	config = function()
		require("conform").setup({
			formatters_by_ft = {
				python = { "ruff_fix", "ruff_format", "ruff_organize_imports", "black", "injected" },
				make = { "bake" },
				sh = { "shfmt" },
				bash = { "shfmt" },
				containerfile = { "dockerfmt" },
				dockerfile = { "dockerfmt" },
				markdown = { "mdformat" },
				lua = { "stylua" },
				json = { "fixjson" },
				yaml = { "yamlfmt" },
				cpp = { "clang-format" },
				cmake = { "cmake_format" },
				sql = { "sqruff" },
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
			formatters = {
				formatters = {
					sqruff = {
						command = "sqruff",
						args = { "format", "-" },
						stdin = true,
						cwd = function()
							return vim.fn.getcwd()
						end,
					},
				},
				injected = {
					-- Set the options field
					options = {
						-- Set to true to ignore errors
						ignore_errors = false,
						-- Map of treesitter language to file extension
						-- A temporary file name with this extension will be generated during formatting
						-- because some formatters care about the filename.
						lang_to_ext = {
							bash = "bash",
							sh = "sh",
							c = "c",
							c_sharp = "cs",
							elixir = "exs",
							javascript = "js",
							julia = "jl",
							latex = "tex",
							markdown = "md",
							python = "py",
							ruby = "rb",
							rust = "rs",
							teal = "tl",
							r = "r",
							typescript = "ts",
						},
					},
				},
			},
		})

		vim.keymap.set({ "n", "v" }, "<leader>mp", function()
			require("conform").format({
				lsp_fallback = true,
				async = false,
				timeout_ms = 1000,
			})
		end, { desc = "conform: Format file or range (in visual mode)" })

		vim.keymap.set("n", "<leader>fl", require("conform").format, { desc = "conform: format" })

		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = "*",
			callback = function(args)
				require("conform").format({ bufnr = args.buf })
			end,
		})
	end,
}
