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
	end,
}
