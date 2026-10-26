vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
dofile("tests/support/tandem.lua")

local state = require("opencode.state")
local util = require("opencode.util")
local model = require("opencode.ephemeral.model")
local preferences = require("opencode.ephemeral.preferences")
local catalog = require("opencode.ephemeral.catalog")
local function equal(actual, expected)
	assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. " ~= " .. vim.inspect(expected))
end

-- Model state survives a new module/session without touching the user's state.
local files, warnings = {}, {}
local old = {
	stat = vim.uv.fs_stat,
	rename = vim.uv.fs_rename,
	timer = vim.uv.new_timer,
	read = vim.fn.readfile,
	write = vim.fn.writefile,
	mkdir = vim.fn.mkdir,
	delete = vim.fn.delete,
	stdpath = vim.fn.stdpath,
	notify = util.notify,
	jobstart = vim.fn.jobstart,
	chansend = vim.fn.chansend,
	chanclose = vim.fn.chanclose,
	jobstop = vim.fn.jobstop,
	select = vim.ui.select,
	input = vim.ui.input,
}
vim.fn.stdpath = function(kind)
	return kind == "state" and "/isolated-state" or old.stdpath(kind)
end
local path = preferences.path()
vim.uv.fs_stat = function(name)
	if files[name] then
		return { type = "file" }
	end
	return nil, "ENOENT"
end
vim.fn.readfile = function(name)
	assert(files[name], "missing file: " .. name)
	return { files[name] }
end
vim.fn.writefile = function(lines, name)
	files[name] = table.concat(lines, "\n")
	return 0
end
vim.fn.mkdir = function()
	return 1
end
vim.fn.delete = function(name)
	files[name] = nil
	return 0
end
vim.uv.fs_rename = function(from, to)
	assert(files[from])
	files[to], files[from] = files[from], nil
	return true
end
util.notify = function(message, level)
	if level == vim.log.levels.WARN then
		warnings[#warnings + 1] = message
	end
end

state.ephemeral_models_loaded = false
model.load()
equal(state.ephemeral_models, {})
equal(#warnings, 0)
model.set("query", " first-model ")
equal(model.get("query"), "first-model")
equal(vim.json.decode(files[path]), { query = "first-model", edit = vim.NIL, commit = vim.NIL })
model.set("edit", "edit-model")
-- Another session saves a query; changing edit must retain that disk preference.
files[path] = vim.json.encode({ query = "other-session", edit = "edit-model" })
model.set("edit", "new-edit")
equal(vim.json.decode(files[path]), { query = "other-session", edit = "new-edit", commit = vim.NIL })
state.ephemeral_models, state.ephemeral_models_loaded = {}, false
package.loaded["opencode.ephemeral.preferences"] = nil
require("opencode.ephemeral.preferences").load()
equal(state.ephemeral_models, { query = "other-session", edit = "new-edit" })
model.set("query", nil)
state.ephemeral_models, state.ephemeral_models_loaded = {}, false
model.load()
equal(state.ephemeral_models, { edit = "new-edit" })
equal(vim.json.decode(files[path]).query, vim.NIL)

model.set("commit", "provider/commit-model#high")
state.ephemeral_models, state.ephemeral_models_loaded = {}, false
model.load()
equal(model.get("commit"), "provider/commit-model#high")
model.set("edit", "another-edit")
equal(vim.json.decode(files[path]).commit, "provider/commit-model#high")
model.set("commit", nil)
equal(vim.json.decode(files[path]).commit, vim.NIL)
equal(model.get("edit"), "another-edit")

files[path] = "{ broken json"
state.ephemeral_models_loaded = false
model.load()
equal(state.ephemeral_models, {})
assert(#warnings > 0)
files[path] = '{"query":42,"edit":"valid-edit"}'
state.ephemeral_models_loaded = false
model.load()
equal(state.ephemeral_models, { edit = "valid-edit" })
files[path] = '{"query":"saved-query","edit":null}'
vim.uv.fs_rename = function()
	return nil, "read-only destination"
end
model.set("query", "session-only")
equal(model.get("query"), "session-only")
equal(vim.json.decode(files[path]).query, "saved-query")
assert(warnings[#warnings]:find("this session only", 1, true))
for name in pairs(files) do
	assert(not name:find(".tmp.", 1, true))
end
vim.fn.writefile = function()
	return -1
end
model.set("edit", "unsaved-edit")
equal(model.get("edit"), "unsaved-edit")
equal(vim.json.decode(files[path]).edit, vim.NIL)
local before = files[path]
model.set("command", "invalid")
equal(files[path], before)

-- Picker choices, cancellation, and superseded requests.
local callbacks, cancelled, picker, selected = {}, 0
local fetch = catalog.fetch
catalog.fetch = function(callback)
	callbacks[#callbacks + 1] = callback
	return function()
		cancelled = cancelled + 1
	end
end
vim.ui.select = function(items, opts, callback)
	picker, selected = { items = items, opts = opts }, callback
end
local saved = preferences.save
preferences.save = function()
	return true
end
state.ephemeral_models_loaded = true
state.ephemeral_models = { query = "unlisted" }
model.select("query")
model.select("edit")
equal(cancelled, 1)
callbacks[1]({}, "live")
equal(picker, nil)
callbacks[2]({ { model = "new-model", label = "New model" } }, "live")
equal(picker.items[2].model, "new-model")
selected(picker.items[2])
equal(model.get("edit"), "new-model")
model.select("query")
callbacks[3]({}, "cached", "offline")
equal(picker.items[2].model, "unlisted")
assert(picker.opts.format_item(picker.items[2]):find("(current)", 1, true))
assert(picker.opts.prompt:find("(cached)", 1, true))
selected(nil)
equal(model.get("query"), "unlisted")
selected(picker.items[1])
equal(model.get("query"), nil)
vim.ui.input = function(_, callback)
	callback("custom-model")
end
selected(picker.items[#picker.items])
equal(model.get("query"), "custom-model")
-- A delayed custom-input callback cannot change a newer picker selection.
local custom_callback
vim.ui.input = function(_, callback)
	custom_callback = callback
end
selected(picker.items[#picker.items])
-- Opening the target picker invalidates a pending discovery.
model.select("query")
model.select_target()
local target_picker = picker
callbacks[4]({}, "live")
equal(picker, target_picker)
custom_callback("stale-model")
equal(model.get("query"), "custom-model")
equal(target_picker.items[1].label, "Edits (file changes)")
equal(target_picker.items[2].label, "Queries (read-only)")
equal(target_picker.items[3], { label = "Commit message", action = "commit" })
selected(target_picker.items[3])
callbacks[5]({ { model = "provider/commit-model", label = "Commit model" } }, "live")
selected(picker.items[2])
equal(model.get("commit"), "provider/commit-model")
model.select_target()
assert(picker.opts.format_item(picker.items[3]):find("provider/commit-model", 1, true))
preferences.save, catalog.fetch = saved, fetch

-- Public command registration, keybindings, and descriptions.
vim.uv.fs_stat, vim.uv.fs_rename, vim.uv.new_timer = old.stat, old.rename, old.timer
vim.fn.readfile, vim.fn.writefile, vim.fn.mkdir = old.read, old.write, old.mkdir
vim.fn.delete, vim.fn.stdpath = old.delete, old.stdpath
vim.fn.jobstart, vim.fn.chansend = old.jobstart, old.chansend
vim.fn.chanclose, vim.fn.jobstop = old.chanclose, old.jobstop
vim.ui.select, vim.ui.input = old.select, old.input
local api = require("opencode")
api.setup()
local commands = vim.api.nvim_get_commands({})
for _, suffix in ipairs({ "", "File", "Selection", "FileDiagnostics", "LineDiagnostics", "SelectionDiagnostics" }) do
	assert(commands["OpenCodeQuery" .. suffix])
	assert(not commands["OpenCodeCommand" .. suffix])
	assert(commands["OpenCodeQuery" .. suffix].definition:find("read-only", 1, true))
end
assert(api.query and api.query_file and api.query_selection and not api.command)
local mapping = vim.fn.maparg("<leader>ac", "n", false, true)
assert(mapping.desc:find("read-only", 1, true))
-- CLI default must omit --model for either action.
local jobs = require("opencode.ephemeral.jobs")
for _, action in ipairs({ "query", "edit" }) do
	local args = assert(jobs.command_args({
		action = action,
		cwd = vim.fn.getcwd(),
		result_message_path = "/unused-result",
	}))
	assert(not vim.tbl_contains(args, "--model"))
end
util.notify = old.notify
print("opencode_ephemeral_models_spec.lua: ok")
