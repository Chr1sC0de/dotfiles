-- Run: nvim --headless -u NONE -i NONE -n -l config/nvim/tests/treesitter_build_test.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local state, records, builds, query_refreshes = {}, {}, {}, {}
local desired = { lua = "lua-v1", markdown = "md-v1", markdown_inline = "inline-v1" }
local query_ids = { lua = "q1", markdown = "q1", markdown_inline = "q1" }
local locked, fail, timeout, remote, resolve_count = false, false, false, false, 0
local b = {}
b.languages = function(selected)
	local result, seen = {}, {}
	for _, lang in ipairs(selected or { "lua", "markdown" }) do
		assert(desired[lang], "unknown language")
		if not seen[lang] then
			table.insert(result, lang)
			seen[lang] = true
		end
		if lang == "markdown" and not seen.markdown_inline then
			table.insert(result, "markdown_inline")
			seen.markdown_inline = true
		end
	end
	return result
end
b.lock = function()
	assert(not locked)
	locked = true
	return function()
		locked = false
	end
end
b.installed = function(lang)
	return state[lang] ~= nil
end
b.artifact = function(lang)
	return state[lang]
end
b.read = function(lang)
	return records[lang]
end
b.write = function(lang, record)
	records[lang] = record
end
b.query_identity = function(lang)
	return query_ids[lang]
end
b.desired = function(lang)
	resolve_count = resolve_count + 1
	assert(not remote, "remote resolution failed")
	return { fingerprint = desired[lang], commit = desired[lang] }
end
b.wait = function()
	assert(not timeout, "timed out")
	-- Scheduled startup ensure must not deadlock a running reconciliation.
	local provision = require("core.treesitter-install")
	if provision._running then
		provision.run("ensure")
	end
end
b.check = function(languages)
	for _, lang in ipairs(languages) do
		assert(state[lang], "missing artifact")
	end
end
b.build = function(lang)
	table.insert(builds, lang)
	assert(fail ~= true, "fixture build failed")
	state[lang] = "artifact:" .. desired[lang]
end
b.refresh_queries = function(lang)
	table.insert(query_refreshes, lang)
end
b.validate = function(_, parser_only)
	assert(parser_only or fail ~= "query", "fixture incompatible query")
end
b.report = function() end
package.loaded["core.treesitter-backend"] = b
local provision = require("core.treesitter-install")
local function run(mode, selected)
	builds, query_refreshes = {}, {}
	return provision.run(mode or "reconcile", selected)
end
local function expect_failure(pattern, mode)
	local ok, err = pcall(run, mode)
	assert(not ok and err:find(pattern, 1, true), tostring(err))
	assert(not locked and not provision._running, "Failure must release lock and reentrancy guard")
end
run()
assert(#builds == 3, "Cold install includes dependencies")
run()
assert(#builds == 0 and #query_refreshes == 0, "Unchanged explicit reconciliation must compile zero parsers")
desired.lua = "lua-v2"
run()
assert(vim.deep_equal(builds, { "lua" }), "Only changed grammar rebuilds")
query_ids.lua = "q2"
run()
assert(#builds == 0 and vim.deep_equal(query_refreshes, { "lua" }), "Query-only changes must not compile")
state.lua = nil
run()
assert(vim.deep_equal(builds, { "lua" }), "Repair missing artifacts")
state.lua = "corrupt"
run()
assert(vim.deep_equal(builds, { "lua" }), "Repair corrupt artifacts")
records.lua = { schema = 999 }
run()
assert(vim.deep_equal(builds, { "lua" }), "Migrate untrusted metadata once")
run()
assert(#builds == 0)
run("rebuild", { "markdown" })
assert(vim.deep_equal(builds, { "markdown" }), "Force selected parser only, not unchanged dependencies")
local before = resolve_count
run("ensure")
assert(resolve_count == before and #builds == 0, "Startup must not query remotes for installed parsers")
desired.lua, fail = "lua-v3", true
local previous = vim.deepcopy(records.lua)
expect_failure("fixture build failed")
assert(vim.deep_equal(records.lua, previous), "Failed builds must not certify metadata")
fail = false
run()
assert(vim.deep_equal(builds, { "lua" }), "Retry failed build")
query_ids.lua, fail = "q3", "query"
previous = vim.deepcopy(records.lua)
expect_failure("fixture incompatible query")
assert(vim.deep_equal(records.lua, previous))
fail = false
run()
assert(#builds == 0 and #query_refreshes == 1)
desired.lua, fail = "lua-v4", "query"
expect_failure("fixture incompatible query")
assert(
	records.lua.fingerprint == "lua-v4" and not records.lua.queries,
	"Persist parser success independently, without certifying broken queries"
)
fail = false
run()
assert(#builds == 0 and #query_refreshes == 1, "Query retry must not rebuild a valid parser")
timeout = true
expect_failure("timed out")
timeout, remote = false, true
expect_failure("remote resolution failed")
remote = false
local ok = pcall(run, "reconcile", { "not_a_language" })
assert(not ok and not locked, "Validate selection before lock/mutation")

local lock = b.lock
b.lock = function()
	error("fixture lock timeout")
end
expect_failure("fixture lock timeout")
b.lock = lock
local commands = {}
provision.run = function(mode, languages)
	table.insert(commands, { mode, languages })
end
provision.setup_commands()
vim.cmd("DotfilesTSUpdate lua")
vim.cmd("DotfilesTSRebuild markdown")
assert(vim.deep_equal(commands, { { "reconcile", { "lua" } }, { "rebuild", { "markdown" } } }))
local spec = dofile("config/nvim/lua/plugins/treesitter.lua")[1]
local loaded = false
package.loaded["lazy.core.loader"] = {
	load = function(plugin, reason)
		assert(plugin == spec and reason.task == "build")
		loaded = true
	end,
}
provision.run = function(mode)
	assert(loaded and mode == "reconcile")
end
spec.build(spec)
print(
	"treesitter_build_test.lua: ok (incremental builds, zero-build repeat, query-only, migration, repair, force, retries, timeout, remote failure, reentrancy, build ordering)"
)
