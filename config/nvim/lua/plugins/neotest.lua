return {
	"nvim-neotest/neotest",
	dependencies = {
		"nvim-neotest/neotest-python",
		"nvim-neotest/nvim-nio",
		"nvim-lua/plenary.nvim",
		"antoinemadec/FixCursorHold.nvim",
		"nvim-treesitter/nvim-treesitter",
	},
	config = function()
		require("neotest").setup({
			adapters = {
				require("neotest-python")({
					-- Extra arguments for nvim-dap configuration
					-- See https://github.com/microsoft/debugpy/wiki/Debug-configuration-settings for values
					dap = { justMyCode = true },
					-- Command line arguments for runner
					-- Can also be a function to return dynamic values
					args = { "--log-level", "DEBUG" },
					-- Runner to use. Will use pytest if available by default.
					-- Can be a function to return dynamic value.
					runner = "pytest",
					-- Custom python path for the runner.
					-- Can be a string or a list of strings.
					-- Can also be a function to return dynamic value.
					-- If not provided, the path will be inferred by checking for
					-- virtual envs in the local directory and for Pipenev/Poetry configs
					python = ".venv/bin/python",
					-- Returns if a given file path is a test file.
					-- NB: This function is called a lot so don't perform any heavy tasks within it.
					-- is_test_file = function(file_path)
					-- end,
					-- !!EXPERIMENTAL!! Enable shelling out to `pytest` to discover test
					-- instances for files containing a parametrize mark (default: false)
					pytest_discover_instances = true,
				}),
			},
		})

		vim.keymap.set("n", "<leader>tn", function()
			require("neotest").run.run()
		end, { desc = "neotest: run nearest" })

		vim.keymap.set("n", "<leader>tf", function()
			require("neotest").run.run(vim.fn.expand("%"))
		end, { desc = "neotest: test file" })

		vim.keymap.set("n", "<leader>td", function()
			require("neotest").run.run({ strategy = "dap" })
		end, { desc = "neotest: debug nearest test" })

		vim.keymap.set("n", "<leader>ts", function()
			require("neotest").run.stop()
		end, { desc = "neotest: stop the nearest test" })

		vim.keymap.set("n", "<leader>ta", function()
			require("neotest").run.attach()
		end, { desc = "neotest: attach the nearest test" })

		vim.keymap.set("n", "<leader>tp", function()
			require("neotest").output.open()
		end, { desc = "neotest: open test panel" })

		vim.keymap.set("n", "<leader>tS", function()
			require("neotest").summary.toggle()
		end, { desc = "neotest: open summary" })
	end,
}
