return {
	"mfussenegger/nvim-dap",
	recommended = true,
	enabled = not vim.g.vscode,
	desc = "Debugging support. Requires language specific adapters to be configured. (see lang extras)",
	dependencies = {
		{
			"rcarriga/nvim-dap-ui",
			dependencies = { "nvim-neotest/nvim-nio" },
		},
		"mfussenegger/nvim-dap-python",
		"theHamsta/nvim-dap-virtual-text",
		"jbyuki/one-small-step-for-vimkind",
	},
	lazy = false,
	config = function()
		local dap = require("dap")
		local dapui = require("dapui")

		dapui.setup({
			layouts = {
				{
					elements = {
						{ id = "console", size = 1 },
					},
					size = 0.25,
					position = "bottom",
				},
			},
		})

		local function dapui_float_element(element, title)
			return function()
				dapui.float_element(element, {
					enter = true,
					position = "center",
					width = math.floor(vim.o.columns * 0.7),
					height = math.floor(vim.o.lines * 0.7),
					title = title,
				})
			end
		end

		-- set the keymaps
		vim.keymap.set("n", "<F5>", function()
			dap.continue()
		end, { desc = "dap: continue" })
		vim.keymap.set("n", "<F17>", function()
			dap.terminate()
		end, { desc = "dap: terminate session" })
		vim.keymap.set("n", "<S-F5>", function()
			dap.terminate()
		end, { desc = "dap: terminate session" })
		vim.keymap.set("n", "<F10>", function()
			dap.step_over()
		end, { desc = "dap: step over" })
		vim.keymap.set("n", "<F11>", function()
			dap.step_into()
		end, { desc = "dap: step into" })
		vim.keymap.set("n", "<F12>", function()
			dap.step_out()
		end, { desc = "dap: step out" })
		vim.keymap.set("n", "<F9>", function()
			dap.toggle_breakpoint()
		end, { desc = "dap: toggle break point" })
		vim.keymap.set("n", "<F21>", function()
			local condition = vim.fn.input("conditional breakpoint")
			dap.set_breakpoint(condition)
		end, { desc = "dap: set conditional break point" })
		vim.keymap.set("n", "<Leader>B", function()
			dap.set_breakpoint()
		end, { desc = "dap: set breakpoint" })
		vim.keymap.set("n", "<Leader>lp", function()
			dap.set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
		end, { desc = "dap: set logpoint message" })
		vim.keymap.set("n", "<Leader>dr", function()
			dap.repl.toggle()
		end, { desc = "dap: toggle repl" })
		vim.keymap.set("n", "<Leader>dt", function()
			dapui.toggle()
		end, { desc = "dap-ui: toggle" })
		vim.keymap.set("n", "<Leader>dS", dapui_float_element("stacks", "Stacks"), { desc = "dap-ui: float stacks" })
		vim.keymap.set("n", "<Leader>dL", dapui_float_element("scopes", "Locals"), { desc = "dap-ui: float locals" })
		vim.keymap.set("n", "<Leader>dT", dapui_float_element("stacks", "Threads"), { desc = "dap-ui: float threads" })
		vim.keymap.set(
			"n",
			"<Leader>dB",
			dapui_float_element("breakpoints", "Breakpoints"),
			{ desc = "dap-ui: float breakpoints" }
		)
		vim.keymap.set("n", "<Leader>dW", dapui_float_element("watches", "Watches"), { desc = "dap-ui: float watches" })

		vim.keymap.set("n", "<Leader>dA", function()
			require("dapui").float_element("repl", {
				enter = true,
				width = math.floor(vim.o.columns * 0.8),
				height = math.floor(vim.o.lines * 0.6),
			})
			require("dap").repl.execute("disassemble ")
		end)

		vim.keymap.set({ "n", "v" }, "<Leader>dh", function()
			require("dap.ui.widgets").hover()
		end, { desc = "dap: hover widgets" })
		vim.keymap.set({ "n", "v" }, "<Leader>dp", function()
			require("dap.ui.widgets").preview()
		end, { desc = "dap: preview widgets" })
		vim.keymap.set("n", "<Leader>df", function()
			local widgets = require("dap.ui.widgets")
			widgets.centered_float(widgets.frames)
		end, { desc = "dap: centered floats frames" })
		vim.keymap.set("n", "<Leader>ds", function()
			local widgets = require("dap.ui.widgets")
			widgets.centered_float(widgets.scopes)
		end, { desc = "dap: centered floats scopes" })

		vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })

		-- setup the dap configurations per use case
		local bash_config = require("dap-conf.bash")
		local dap_python = require("dap-python")

		dap_python.setup("uv")
		dap_python.test_runner = "pytest"

		dap.adapters.bashdb = bash_config.adapter
		dap.configurations.sh = bash_config.configuration
		dap.configurations.bash = bash_config.configuration

		dap.configurations.lua = {
			{
				type = "nlua",
				request = "attach",
				name = "Attach to running Neovim instance",
			},
		}

		dap.adapters.nlua = function(callback, config)
			callback({ type = "server", host = config.host or "127.0.0.1", port = config.port or 8086 })
		end

		for name, sign in pairs({
			Stopped = { "󰁕 ", "DiagnosticWarn", "DapStoppedLine" },
			Breakpoint = "",
			BreakpointCondition = " ",
			BreakpointRejected = { " ", "DiagnosticError" },
			LogPoint = ".>",
		}) do
			sign = type(sign) == "table" and sign or { sign }
			vim.fn.sign_define(
				"Dap" .. name,
				{ text = sign[1], texthl = sign[2] or "DiagnosticInfo", linehl = sign[3], numhl = sign[3] }
			)
		end

		vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = "#24272e" }) -- Change bg to your preferred color
	end,
}
