vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
dofile("tests/support/tandem.lua")

local state = require("codex.state")
local util = require("codex.util")
local model = require("codex.ephemeral.model")
local preferences = require("codex.ephemeral.preferences")
local catalog = require("codex.ephemeral.catalog")
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
equal(vim.json.decode(files[path]), { query = "first-model", edit = vim.NIL })
model.set("edit", "edit-model")
-- Another session saves a query; changing edit must retain that disk preference.
files[path] = vim.json.encode({ query = "other-session", edit = "edit-model" })
model.set("edit", "new-edit")
equal(vim.json.decode(files[path]), { query = "other-session", edit = "new-edit" })
state.ephemeral_models, state.ephemeral_models_loaded = {}, false
package.loaded["codex.ephemeral.preferences"] = nil
require("codex.ephemeral.preferences").load()
equal(state.ephemeral_models, { query = "other-session", edit = "new-edit" })
model.set("query", nil)
state.ephemeral_models, state.ephemeral_models_loaded = {}, false
model.load()
equal(state.ephemeral_models, { edit = "new-edit" })
equal(vim.json.decode(files[path]).query, vim.NIL)

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

-- Exercise the actual JSON protocol using controlled process and timer boundaries.
local process, timer, sent, stopped, closed, starts, response
local previous_home, previous_binary = vim.env.CODEX_HOME, vim.env.CODEX_REAL_BIN
vim.env.CODEX_HOME = "/catalog-home"
vim.env.CODEX_REAL_BIN = "/real-codex"
local cache = "/catalog-home/models_cache.json"
files[cache] =
	'{"models":[{"slug":"cached","display_name":"Cached","visibility":"list"},{"slug":"hidden","visibility":"hide"}]}'
vim.fn.jobstart = function(argv, opts)
	equal(argv, { "/real-codex", "app-server", "--listen", "stdio://" })
	starts = (starts or 0) + 1
	process = opts
	return 91
end
vim.fn.chansend = function(_, bytes)
	sent[#sent + 1] = vim.json.decode(bytes)
	return #bytes
end
vim.fn.chanclose = function()
	closed = closed + 1
end
vim.fn.jobstop = function()
	stopped = stopped + 1
end
vim.uv.new_timer = function()
	timer = { closing = false }
	function timer:start(timeout, interval, callback)
		equal(timeout, 10000)
		equal(interval, 0)
		self.callback = callback
	end
	function timer:is_closing()
		return self.closing
	end
	function timer:stop()
		self.stopped = true
	end
	function timer:close()
		self.closing = true
	end
	return timer
end
local function begin()
	sent, stopped, closed, response = {}, 0, 0, nil
	return catalog.fetch(function(items, source, err)
		response = { items = items, source = source, err = err }
	end)
end
local function emit(value)
	process.on_stdout(91, { vim.json.encode(value), "" })
end
local function initialized()
	emit({ id = 1, result = {} })
	equal(sent[2].method, "initialized")
	equal(sent[3].method, "model/list")
	equal(sent[3].params.includeHidden, false)
end
local function finish()
	assert(vim.wait(100, function()
		return response ~= nil
	end))
	return response
end
begin()
equal(sent[1].method, "initialize")
-- Notifications and another request's response must not affect the handshake.
emit({ method = "status", params = {} })
emit({ id = 50, result = {} })
initialized()
local bytes = vim.json.encode({
	id = 2,
	result = {
		data = { { model = "a", displayName = "Model A" }, { model = "hidden", hidden = true } },
		nextCursor = "page-2",
	},
})
process.on_stdout(91, { bytes:sub(1, 12) })
process.on_stdout(91, { bytes:sub(13), "" })
equal(sent[4].params.cursor, "page-2")
emit({ id = 3, result = { data = { { model = "a" }, { model = "b" } }, nextCursor = vim.NIL } })
equal(finish().items, { { model = "a", label = "Model A" }, { model = "b", label = "b" } })
equal(response.source, "live")
equal(stopped, 1)
equal(closed, 1)
assert(timer.closing)
process.on_exit(91, 0)
equal(response.source, "live")

begin()
timer.callback()
equal(finish().source, "cached")
equal(response.items, { { model = "cached", label = "Cached" } })
equal(stopped, 1)

begin()
emit({ id = 1, error = { code = -1 } })
equal(finish().source, "cached")
begin()
process.on_stdout(91, { "not-json", "" })
equal(finish().source, "cached")
begin()
initialized()
emit({ id = 2, result = { data = {}, nextCursor = "repeat" } })
emit({ id = 3, result = { data = {}, nextCursor = "repeat" } })
equal(finish().source, "cached")
begin()
process.on_exit(91, 1)
equal(finish().source, "cached")

local start = vim.fn.jobstart
vim.fn.jobstart = function()
	return -1
end
begin()
equal(finish().source, "cached")
files[cache] = "bad-json"
begin()
equal(finish().source, "unavailable")
equal(response.items, {})
vim.fn.jobstart = start
local cancel = begin()
cancel()
process.on_exit(91, 0)
vim.wait(10, function()
	return false
end)
equal(response, nil)
equal(stopped, 1)
assert(timer.closing)

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
preferences.save, catalog.fetch = saved, fetch

-- Public command registration, keybindings, and descriptions.
vim.uv.fs_stat, vim.uv.fs_rename, vim.uv.new_timer = old.stat, old.rename, old.timer
vim.fn.readfile, vim.fn.writefile, vim.fn.mkdir = old.read, old.write, old.mkdir
vim.fn.delete, vim.fn.stdpath = old.delete, old.stdpath
vim.fn.jobstart, vim.fn.chansend = old.jobstart, old.chansend
vim.fn.chanclose, vim.fn.jobstop = old.chanclose, old.jobstop
vim.ui.select, vim.ui.input = old.select, old.input
vim.env.CODEX_HOME, vim.env.CODEX_REAL_BIN = previous_home, previous_binary
local api = require("codex")
api.setup()
local commands = vim.api.nvim_get_commands({})
for _, suffix in ipairs({ "", "File", "Selection", "FileDiagnostics", "LineDiagnostics", "SelectionDiagnostics" }) do
	assert(commands["CodexQuery" .. suffix])
	assert(not commands["CodexCommand" .. suffix])
	assert(commands["CodexQuery" .. suffix].definition:find("read-only", 1, true))
end
assert(api.query and api.query_file and api.query_selection and not api.command)
local mapping = vim.fn.maparg("<leader>ac", "n", false, true)
assert(mapping.desc:find("read-only", 1, true))
-- CLI default must omit --model for either action.
local jobs = require("codex.ephemeral.jobs")
for _, action in ipairs({ "query", "edit" }) do
	local args = assert(jobs.command_args({
		action = action,
		cwd = vim.fn.getcwd(),
		result_message_path = "/unused-result",
	}))
	assert(not vim.tbl_contains(args, "--model"))
end
util.notify = old.notify
print("codex_ephemeral_models_spec.lua: ok")
