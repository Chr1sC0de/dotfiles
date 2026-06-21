return {
	"Civitasv/cmake-tools.nvim",
	opts = {},
	config = function()
		require("cmake-tools").setup({
			cmake_executor = { -- executor to use
				name = "overseer", -- name of the executor
				default_opts = { -- a list of default and possible values for executors
					overseer = {
						on_new_task = function(task)
							require("overseer").open({ enter = false, direction = "bottom" })
						end, -- a function that gets overseer.Task when it is created, before calling `task:start`
					},
				},
			},
			cmake_runner = { -- runner to use
				name = "overseer", -- name of the runner
				default_opts = { -- a list of default and possible values for runners
					overseer = {
						on_new_task = function(task)
							require("overseer").open({ enter = false, direction = "bottom" })
						end, -- a function that gets overseer.Task when it is created, before calling `task:start`
					},
				},
			},
		})

		vim.keymap.set("n", "<leader>cg", ":CMakeGenerate<cr>", { desc = "cmake: generate" })
		vim.keymap.set("n", "<leader>cb", ":CMakeBuild<cr>", { desc = "cmake: build" })
		vim.keymap.set("n", "<leader>cr", ":CMakeRun<cr>", { desc = "cmake: run" })
		vim.keymap.set("n", "<leader>cR", ":CMakeRunTest<cr>", { desc = "cmake: run test" })
		vim.keymap.set("n", "<leader>cd", ":CMakeDebug<cr>", { desc = "cmake: debug" })
		vim.keymap.set("n", "<leader>cD", ":CMakeDebugCurrentFile<cr>", { desc = "cmake: debug current file" })
		vim.keymap.set("n", "<leader>cL", ":CMakeLaunchArgs ", { desc = "cmake: launch args" })
		vim.keymap.set("n", "<leader>cC", ":CMakeClean<cr>", { desc = "cmake: clean" })
	end,
}
