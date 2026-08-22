vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.g.mapleader = " "

local standalone_toggle_calls = 0
local dap = {
	adapters = {},
	configurations = { python = {} },
	repl = {
		toggle = function()
			standalone_toggle_calls = standalone_toggle_calls + 1
		end,
	},
}

package.loaded.dap = dap
package.loaded["dap-python"] = {
	setup = function() end,
}

local repl_buffer = vim.api.nvim_create_buf(false, true)
local dapui_open_calls = 0
local dapui = {
	elements = {
		repl = {
			buffer = function()
				return repl_buffer
			end,
		},
	},
	float_element = function() end,
	open = function()
		dapui_open_calls = dapui_open_calls + 1
		vim.cmd("belowright split")
		vim.api.nvim_win_set_buf(0, repl_buffer)
	end,
	setup = function() end,
	toggle = function() end,
}

package.loaded.dapui = dapui

local source_window = vim.api.nvim_get_current_win()
local spec = dofile(vim.fn.getcwd() .. "/config/nvim/lua/plugins/nvim-dap.lua")
spec.config()

local repl_mapping = vim.fn.maparg("<Leader>dr", "n", false, true)
assert(type(repl_mapping.callback) == "function", "DAP REPL mapping should have a Lua callback")

vim.cmd("belowright vsplit")
local repl_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(repl_window, repl_buffer)
vim.api.nvim_set_current_win(source_window)

repl_mapping.callback()
assert(vim.api.nvim_get_current_win() == repl_window, "visible DAP UI REPL should receive focus")
assert(dapui_open_calls == 0, "visible DAP UI should not be reopened")

repl_mapping.callback()
assert(vim.api.nvim_get_current_win() == source_window, "REPL focus toggle should return to the source window")
assert(vim.api.nvim_win_is_valid(repl_window), "returning focus should leave the DAP UI open")

vim.api.nvim_win_close(repl_window, true)
repl_mapping.callback()
assert(dapui_open_calls == 1, "hidden DAP UI should be opened once")
assert(vim.api.nvim_get_current_buf() == repl_buffer, "newly opened DAP UI REPL should receive focus")

local reopened_repl_window = vim.api.nvim_get_current_win()
repl_mapping.callback()
assert(vim.api.nvim_get_current_win() == source_window, "hidden DAP UI round trip should return to the source")
assert(vim.api.nvim_win_is_valid(reopened_repl_window), "focus toggle should not close a newly opened DAP UI")

vim.cmd("belowright vsplit")
local stale_source_window = vim.api.nvim_get_current_win()
repl_mapping.callback()
assert(vim.api.nvim_get_current_win() == reopened_repl_window, "new source window should be remembered")
vim.api.nvim_win_close(stale_source_window, true)

local returned, return_error = pcall(repl_mapping.callback)
assert(returned, "closed return window should not raise an error: " .. tostring(return_error))
assert(
	vim.api.nvim_get_current_win() == source_window,
	"closed return window should fall back to another source window"
)
assert(vim.api.nvim_win_get_buf(reopened_repl_window) == repl_buffer, "fallback should not replace the DAP UI buffer")
assert(standalone_toggle_calls == 0, "DAP UI mapping should not toggle the standalone REPL")

print("dap_repl_ui_test.lua: ok")
