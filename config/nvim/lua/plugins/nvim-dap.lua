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

		-- The REPL and the debuggee console live in separate layouts so they can
		-- be toggled independently. Both share the bottom area, so opening one
		-- replaces the other instead of stacking splits.
		local DAPUI_REPL = 1
		local DAPUI_CONSOLE = 2

		dapui.setup({
			layouts = {
				{
					elements = {
						{ id = "repl", size = 1 },
					},
					size = 0.35,
					position = "bottom",
				},
				{
					elements = {
						{ id = "console", size = 1 },
					},
					size = 0.35,
					position = "bottom",
				},
			},
		})

		local dapui_windows = require("dapui.windows")

		-- Work directly with the layouts instead of dapui.open()/dapui.toggle() so
		-- that each UI can be shown on its own. Keep the cursor where it is.
		local function close_layouts_except(index)
			for i, layout in ipairs(dapui_windows.layouts) do
				if i ~= index and layout:is_open() then
					layout:close()
				end
			end
		end

		local function open_layout(index)
			close_layouts_except(index)
			local layout = dapui_windows.layouts[index]
			if layout and not layout:is_open() then
				layout:open()
			end
		end

		local function toggle_layout(index)
			local layout = dapui_windows.layouts[index]
			if not layout then
				return
			end
			if layout:is_open() then
				layout:close()
			else
				open_layout(index)
			end
		end

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

		local repl_return_windows = {}

		local function valid_repl_return_window(window, tabpage, repl_buffer)
			return window
				and vim.api.nvim_win_is_valid(window)
				and vim.api.nvim_win_get_tabpage(window) == tabpage
				and vim.api.nvim_win_get_buf(window) ~= repl_buffer
		end

		local function repl_return_window(tabpage, repl_buffer)
			local remembered_window = repl_return_windows[tabpage]
			if valid_repl_return_window(remembered_window, tabpage, repl_buffer) then
				return remembered_window
			end

			local alternate_window = vim.fn.win_getid(vim.fn.winnr("#"))
			if valid_repl_return_window(alternate_window, tabpage, repl_buffer) then
				return alternate_window
			end

			for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
				if valid_repl_return_window(window, tabpage, repl_buffer) then
					return window
				end
			end
		end

		local function toggle_dapui_repl_focus()
			local tabpage = vim.api.nvim_get_current_tabpage()
			local repl_buffer = dapui.elements.repl.buffer()

			if vim.api.nvim_get_current_buf() == repl_buffer then
				local return_window = repl_return_window(tabpage, repl_buffer)
				if return_window then
					repl_return_windows[tabpage] = return_window
					vim.api.nvim_set_current_win(return_window)
				end
				return
			end

			repl_return_windows[tabpage] = vim.api.nvim_get_current_win()
			local repl_window = vim.fn.bufwinid(repl_buffer)

			if repl_window == -1 then
				open_layout(DAPUI_REPL)
				repl_buffer = dapui.elements.repl.buffer()
				repl_window = vim.fn.bufwinid(repl_buffer)
			end

			if repl_window ~= -1 then
				vim.api.nvim_set_current_win(repl_window)
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
			local condition = vim.fn.input("conditional breakpoint (shift+F9=F21)")
			dap.set_breakpoint(condition)
		end, { desc = "dap: set conditional break point" })
		vim.keymap.set("n", "<Leader>B", function()
			dap.set_breakpoint()
		end, { desc = "dap: set breakpoint" })
		vim.keymap.set("n", "<Leader>lp", function()
			dap.set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
		end, { desc = "dap: set logpoint message" })
		vim.keymap.set("n", "<Leader>di", function()
			toggle_layout(DAPUI_REPL)
		end, { desc = "dap-ui: toggle repl" })
		vim.keymap.set("n", "<Leader>do", function()
			toggle_layout(DAPUI_CONSOLE)
		end, { desc = "dap-ui: toggle terminal" })
		vim.keymap.set("n", "<Leader>du", toggle_dapui_repl_focus, { desc = "dap-ui: toggle repl focus" })
		vim.keymap.set("n", "<Leader>dS", dapui_float_element("stacks", "Stacks"), { desc = "dap-ui: float stacks" })
		vim.keymap.set("n", "<Leader>dL", dapui_float_element("scopes", "Locals"), { desc = "dap-ui: float locals" })
		vim.keymap.set("n", "<Leader>dT", dapui_float_element("stacks", "Threads"), { desc = "dap-ui: float threads" })
		vim.keymap.set("n", "<Leader>dC", dapui_float_element("console", "Console"), { desc = "dap-ui: float console" })
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
		end, { desc = "dap-ui: disassemble" })

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

		for _, config in ipairs(dap.configurations.python) do
			config.cwd = "${workspaceFolder}"
		end

		dap.adapters.bash = bash_config.adapter
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
