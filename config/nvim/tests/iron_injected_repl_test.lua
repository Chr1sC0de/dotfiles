vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")

local sent_filetype
local toggled_filetype

local iron = {
	send_line = function() end,
	send_mark = function() end,
	send_until_cursor = function() end,
	setup = function() end,
	send = function(filetype)
		sent_filetype = filetype
	end,
	repl_for = function(filetype)
		toggled_filetype = filetype
	end,
	mark_visual = function() end,
	mark_motion = function() end,
	run_motion = function() end,
}

package.loaded["iron.core"] = iron
package.loaded["iron.lowlevel"] = {
	get_repl_def = function(filetype)
		if filetype == "python" then
			return { command = { "python" } }
		end
		error("unsupported filetype " .. filetype)
	end,
}
package.loaded["iron.marks"] = {
	set = function() end,
	get = function() end,
}
package.loaded["iron.state"] = {}
package.loaded["iron.view"] = {
	split = setmetatable({
		vertical = {
			rightbelow = function()
				return "vertical"
			end,
		},
		rightbelow = function()
			return "horizontal"
		end,
	}, {
		__index = function()
			return function() end
		end,
	}),
}
package.loaded["iron.fts.common"] = {
	bracketed_paste_python = function(lines)
		return lines
	end,
}

local parsed_language = "python"
local language_tree = {
	lang = function()
		return parsed_language
	end,
	included_regions = function()
		return { { { 0, 0, 0, 0, 8, 8 } } }
	end,
}

vim.treesitter.get_parser = function()
	return {
		parse = function() end,
		language_for_range = function()
			return language_tree
		end,
	}
end

local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buffer)
vim.bo[buffer].filetype = "markdown"
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "print(1)" })

local spec = dofile(vim.fn.getcwd() .. "/config/nvim/lua/plugins/iron-nvim.lua")
spec.config()

local send_line = vim.fn.maparg("<space>sl", "n", false, true).callback
assert(type(send_line) == "function", "injected send-line mapping should have a Lua callback")
send_line()
assert(sent_filetype == "python", "injected line should be sent to the Python REPL")

-- The cursor may leave the injected region before the user toggles the REPL.
parsed_language = "markdown"

local toggle_repl = vim.fn.maparg("<space>rr", "n", false, true).callback
assert(type(toggle_repl) == "function", "REPL toggle should have an injection-aware Lua callback")
toggle_repl()
assert(toggled_filetype == "python", "REPL toggle should target the last injected filetype")

print("iron_injected_repl_test.lua: ok")
