vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local backend = require("opencode.backend")
local catalog = require("opencode.ephemeral.catalog")
local cache = vim.fn.tempname() .. "/models.json"
catalog.cache_path = function() return cache end
local id, lines, failure = backend.parse_events({
	'not JSON',
	'{"type":"step_start","sessionID":"ses_test"}',
	'{"type":"text","sessionID":"ses_test","part":{"text":"answer\\nsecond line"}}',
})
assert(id == "ses_test" and table.concat(lines, "\n") == "answer\nsecond line" and not failure)
local _, _, error = backend.parse_events({ '{"type":"error","error":{"message":"failed"}}' })
assert(error:find("failed", 1, true))
local previous = vim.env.OPENCODE_CONFIG_CONTENT
vim.env.OPENCODE_CONFIG_CONTENT = '{"model":"fixture/test","plugins":["host-plugin"]}'
local env = assert(backend.environment(nil, { text_only = true }))
local config = vim.json.decode(env.OPENCODE_CONFIG_CONTENT)
assert(config.model == "fixture/test" and config.plugins[1] == "host-plugin")
assert(config.plugins[2].options.text_only)
assert(config.policies[#config.policies].effect == "deny")
vim.env.OPENCODE_CONFIG_CONTENT = 'invalid'
assert(backend.environment() == nil)
vim.env.OPENCODE_CONFIG_CONTENT = previous

local old_system, callback, killed = vim.system, nil, false
vim.system = function(args, opts, cb)
	assert(vim.deep_equal(args, { "opencode", "api", "get", "/api/model" }))
	assert(opts.timeout == 10000)
	callback = cb
	return { kill = function() killed = true end }
end
local response
catalog.fetch(function(choices, source) response = { choices, source } end)
callback({ code = 0, stdout = vim.json.encode({ data = {
	{ id = "a", providerID = "fixture", name = "A", enabled = true, settings = { apiKey = "do-not-retain" }, variants = { { id = "low" } } },
	{ id = "hidden", providerID = "fixture", enabled = false },
} }) })
assert(vim.wait(1000, function() return response ~= nil end))
assert(#response[1] == 2 and response[1][1].model == "fixture/a" and response[1][2].model == "fixture/a#low")
assert(not vim.json.encode(response):find("do-not-retain", 1, true))
assert(not table.concat(vim.fn.readfile(cache), "\n"):find("do-not-retain", 1, true))
response = nil
catalog.fetch(function(choices, source) response = { choices, source } end)
callback({ code = 1, stdout = "" })
assert(vim.wait(1000, function() return response ~= nil end))
assert(response[2] == "cached" and #response[1] == 2)
response = nil
local cancel = catalog.fetch(function() response = true end)
cancel()
callback({ code = 1, stdout = "" })
vim.wait(20, function() return false end)
assert(killed and response == nil)
vim.system = old_system
vim.fn.delete(vim.fs.dirname(cache), "rf")
print("opencode_backend_spec.lua: ok")
