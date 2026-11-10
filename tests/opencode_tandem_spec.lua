vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local tandem = require("agents.tandem")
local root = vim.uv.fs_realpath(vim.fn.getcwd())
local original_system = vim.system
local pending, calls = {}, {}
vim.system = function(args, _, callback)
	calls[#calls + 1] = args
	pending[#pending + 1] = callback
	return {}
end
local opts = { command = vim.v.progpath, root = root, interval_ms = 20, backoff_cap_ms = 40 }
tandem.setup(opts)
assert(vim.wait(1000, function()
	return #pending == 1
end))
assert(calls[1][4] == "editor" and calls[1][5] == "register")
assert(calls[1][7] == vim.v.servername)
assert(not tandem.config(root))
local first = table.remove(pending, 1)
first({ code = 0, stdout = '{"ok":true,"editor":"editor-one"}' })
assert(vim.wait(1000, function()
	return tandem.status().connected
end))
local config = assert(tandem.config(root))
assert(config.tandem.editor == "editor-one")
assert(not tandem.config("/"))
assert(not tandem.config(root, false, "/outside.txt"))
assert(vim.wait(1000, function()
	return #pending == 1
end))
table.remove(pending, 1)({ code = 1, stderr = "daemon restarting" })
assert(vim.wait(1000, function()
	return not tandem.status().connected
end))
assert(not tandem.config(root))
assert(vim.wait(1000, function()
	return #pending == 1
end))
table.remove(pending, 1)({ code = 0, stdout = '{"ok":true,"editor":"editor-one"}' })
assert(vim.wait(1000, function()
	return tandem.status().connected
end))
assert(tandem.config(root).tandem.editor == "editor-one")
assert(vim.wait(1000, function()
	return #pending == 1
end))
local stale = table.remove(pending, 1)
tandem.setup(opts)
stale({ code = 0, stdout = '{"ok":true,"editor":"wrong-editor"}' })
assert(vim.wait(1000, function()
	return #pending == 1
end))
assert(not tandem.status().connected)
local last = table.remove(pending, 1)
tandem.stop()
last({ code = 0, stdout = '{"ok":true,"editor":"after-stop"}' })
vim.wait(50)
assert(not tandem.status().connected)
vim.system = original_system
print("opencode_tandem_spec.lua: ok")
