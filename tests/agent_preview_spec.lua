vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
local preview = require("workmux.agent_preview")
local Job = require("snacks.util.job")
_G.Snacks = { debug = {
	cmd = function(message)
		error(vim.inspect(message))
	end,
} }

local buf = vim.api.nvim_create_buf(false, true)
local win = vim.api.nvim_open_win(buf, true, { relative = "editor", row = 0, col = 0, width = 8, height = 4 })
local sends, captures, callback, killed = {}, 0, nil, false
local original_send, original_system = vim.api.nvim_chan_send, vim.system
vim.api.nvim_chan_send = function(chan, data)
	sends[#sends + 1] = data
	return original_send(chan, data)
end
vim.system = function(_, opts, cb)
	assert(opts.timeout == 2000)
	captures = captures + 1
	callback = cb
	return {
		kill = function()
			killed = true
		end,
	}
end
package.loaded["snacks.picker.preview"] = {
	cmd = function(command, _, opts)
		return Job.new(buf, command, opts)
	end,
}
local title
local command = { "sh", "-c", "printf '\27[48;2;20;30;40m12345678\27[0m\nsecond\nthird'" }
preview.cmd(
	command,
	{ win = win, preview = {
		set_title = function(value)
			title = value
		end,
	} },
	{ term = false, ansi = true }
)
assert(
	vim.wait(1000, function()
		return captures == 1
	end),
	"preview did not refresh"
)
assert(sends[1]:find("\27[48;2;20;30;40m", 1, true), "background was lost")
local function lines()
	return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
assert(lines()[1] == "12345678", "rightmost cell was erased: " .. vim.inspect(lines()))
local count = #sends
vim.wait(250, function()
	return false
end)
assert(captures == 1, "slow captures overlapped")
callback({ code = 0, stdout = "\27[48;2;20;30;40m12345678\27[0m\nsecond\nthird" })
assert(vim.wait(1000, function()
	return captures == 2
end))
assert(#sends == count, "unchanged snapshot repainted")
callback({ code = 0, stdout = "\27[48;2;20;30;40m12345678\27[0m\nnew" })
assert(vim.wait(1000, function()
	return captures == 3
end))
assert(not sends[#sends]:find("\27[1;1H\27[0m", 1, true), "unchanged first row repainted")
assert(lines()[2] == "new" and (lines()[3] or "") == "", "stale rows survived")
-- Resizing forces a fresh crop even when the source snapshot stays identical.
vim.api.nvim_win_set_width(win, 4)
callback({ code = 0, stdout = "\27[48;2;20;30;40m12345678\27[0m\nnew" })
assert(vim.wait(1000, function()
	return captures == 4
end))
assert(lines()[1] == "1234", "resize did not recrop: " .. vim.inspect(lines()))
local late = callback
vim.api.nvim_win_close(win, true)
assert(killed, "closing preview did not cancel the pending capture")
count = #sends
late({ code = 0, stdout = "stale frame" })
vim.wait(200, function()
	return false
end)
assert(#sends == count and captures == 4, "late result repainted or restarted a closed preview")

local cropped = preview._rows("\27[48;2;20;30;40m🙂abcdef\nnext", 5, 2)
assert(cropped[1]:find("🙂abc", 1, true) and not cropped[1]:find("abcdef", 1, true))
assert(cropped[2]:find("\27[48;2;20;30;40m", 1, true), "inherited row background lost")
assert(title == nil)
vim.api.nvim_chan_send, vim.system = original_send, original_system
print("agent_preview_spec.lua: ok")
