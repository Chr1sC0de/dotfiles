return {
	"igorlfs/nvim-dap-view",
	dependencies = "mfussenegger/nvim-dap",
	config = function()
		require("dap-view.setup").setup({
			winbar = {
				default_section = "repl",
				sections = { "watches", "scopes", "exceptions", "breakpoints", "threads", "repl", "console" },
			},
			windows = {
				size = 0.4,
				terminal = {
					-- 'left'|'right'|'above'|'below': Terminal position in layout
					position = "right",
					-- List of debug adapters for which the terminal should be ALWAYS hidden
					-- hide = { "debugpy", "neotest", "python", "neotest-python" },
					-- Hide the terminal when starting a new session
				},
			},
			-- Controls how to jump when selecting a breakpoint or navigating the stack
			switchbuf = "usetab",
		})

		local dap = require("dap")

		dap.listeners.before.initialize["dap-view-config"] = function()
			require("dap-view").open()
		end

		dap.listeners.before.launch["dap-view-config"] = function()
			require("dap-view").open()
		end

		dap.listeners.before.attach["dap-view-config"] = function()
			require("dap-view").open()
		end

		dap.listeners.before.event_terminated["dap-view-config"] = function()
			require("dap-view").close()
		end
		dap.listeners.before.event_exited["dap-view-config"] = function()
			require("dap-view").close()
		end

		vim.keymap.set({ "n", "v" }, "<leader>de", function()
			require("dap-view").eval(nil, { enter = true })
		end, { desc = "nvim-dap-view: evaluate" })

		vim.keymap.set({ "n", "v" }, "<leader>dt", function()
			require("dap-view").toggle()
		end, { desc = "nvim-dap-view: toggle" })
	end,
}
