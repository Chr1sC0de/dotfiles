vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
dofile("tests/support/tandem.lua")
local chat = require("opencode.chat")
local herdr = require("opencode.herdr")
local attachment = require("opencode.attachment")

vim.notify = function() end
vim.fn.executable = function()
	return 1
end
vim.fn.jobstart = function()
	return 42
end
vim.fn.jobwait = function()
	return { -1 }
end
vim.fn.serverstart = function()
	return "test-hook-server"
end
herdr.available = function()
	return false
end

local lookups, prompts = 0, 0
attachment.load = function()
	return { name = "old-agent", pane_id = "old-pane" }
end
herdr.get_agent = function(_, callback)
	lookups = lookups + 1
	callback(nil, "Old agent is unavailable")
end
vim.ui.select = function(_, _, callback)
	prompts = prompts + 1
	callback(nil)
end

local editor = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(editor, "toggle-test-editor")
-- Exercise the same new/toggle entry points used by <leader>an and <leader>aa.
assert(chat.new())
local session = chat.active_session()
assert(session and session.bufnr ~= editor and vim.api.nvim_get_current_buf() == session.bufnr)
chat.toggle()
assert(vim.api.nvim_get_current_buf() == editor, "toggle must return to the editor")
chat.toggle()
assert(prompts == 0, "a live new chat must not prompt to reattach the old agent")
assert(lookups == 0, "a live chat must take precedence over remembered attachments")
assert(vim.api.nvim_get_current_buf() == session.bufnr, "toggle must return to the new chat")

-- With no live chat, the saved attachment still provides the fallback.
chat.toggle()
session.exited = true
chat.toggle()
assert(lookups == 1 and prompts == 1, "unavailable remembered agents must still offer reattachment")
print("opencode_toggle_active_spec.lua: ok")
