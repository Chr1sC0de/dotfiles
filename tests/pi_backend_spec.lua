vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local pi = require("agents.backends.pi")
local function event(value)
	return vim.json.encode(value)
end
local id, answer, failure = pi.parse_events({
	'{"type":"session","id":"native-pi-id"}',
	"partial or non-JSON line",
	event({ type = "message_update", assistantMessageEvent = { type = "text_delta", delta = "do not duplicate" } }),
	event({
		type = "message_end",
		message = { role = "assistant", stopReason = "toolUse", content = { { type = "toolCall", name = "bash" } } },
	}),
	event({
		type = "message_end",
		message = {
			role = "assistant",
			stopReason = "stop",
			content = { { type = "text", text = "Final answer\nsecond line" } },
		},
	}),
})
assert(id == "native-pi-id" and table.concat(answer, "\n") == "Final answer\nsecond line" and not failure)
local _, _, err = pi.parse_events({
	event({
		type = "message_end",
		message = { role = "assistant", stopReason = "error", errorMessage = "provider failed", content = {} },
	}),
})
assert(err == "provider failed")
local _, _, retry = pi.parse_events({
	event({
		type = "message_end",
		message = { role = "assistant", stopReason = "error", errorMessage = "transient", content = {} },
	}),
	event({
		type = "message_end",
		message = {
			role = "assistant",
			stopReason = "stop",
			content = { { type = "text", text = "Recovered" } },
		},
	}),
})
assert(not retry)
local args = pi.run_args({ text_only = true, model = "provider/model" })
for _, flag in ipairs({ "--no-tools", "--no-extensions", "--no-mcp", "--no-session", "--print", "--mode" }) do
	assert(vim.tbl_contains(args, flag))
end
assert(not vim.tbl_contains(args, "--extension"))
local query = pi.run_args({ action = "query", thread_id = "native-id" })
assert(vim.tbl_contains(query, "--session") and vim.tbl_contains(query, "native-id"))
assert(vim.tbl_contains(query, pi.plugin_path()))
local env = pi.environment({
	tandem = { command = "/bin/tandem", root = "/project", editor = "specific", state_home = "/state" },
})
assert(env.TANDEM_EDITOR == "specific" and env.XDG_STATE_HOME == "/state" and not env.OPENCODE_CONFIG_CONTENT)
local catalog = require("agents.ephemeral.catalog")
local cache = vim.fn.tempname()
catalog.cache_path = function()
	return cache
end
local callback, choices
vim.system = function(command, _, cb)
	assert(vim.deep_equal(command, { "pi", "--offline", "--list-models" }))
	callback = cb
	return { kill = function() end }
end
catalog.fetch(function(result)
	choices = result
end, "pi")
callback({ code = 0, stdout = "provider  model  context\nfixture  test  128K\n" })
assert(vim.wait(1000, function()
	return choices ~= nil
end))
assert(#choices == 1 and choices[1].model == "fixture/test")
vim.fn.delete(cache)
print("pi_backend_spec.lua: ok")
