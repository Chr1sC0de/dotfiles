-- Run: nvim --headless -u NONE -i NONE -n -l config/nvim/tests/treesitter_build_test.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local installed, updates, installs, waits = {}, {}, {}, {}
local timeout, fail = false, false
package.loaded["tree-sitter-manager.config"] = { cfg = { ensure_installed = { "lua", "markdown", "lua" } } }
package.loaded["tree-sitter-manager.util"] = {
	get_requires = function(lang)
		return lang == "markdown" and { "markdown_inline" } or {}
	end,
	is_installed = function(lang)
		return installed[lang] == true
	end,
}
local installer = { status = {} }
installer.wait = function(languages, limit)
	assert(limit == 600000)
	table.insert(waits, vim.deepcopy(languages))
	return not timeout
end
local function complete(languages)
	for _, lang in ipairs(languages) do
		installed[lang] = not fail
		installer.status[lang] = { ok = not fail, error = fail and "fixture build failure" or nil }
	end
end
installer.install = function(languages)
	table.insert(installs, vim.deepcopy(languages))
	complete(languages)
end
installer.update = function(languages)
	table.insert(updates, vim.deepcopy(languages))
	complete(languages)
end
package.loaded["tree-sitter-manager.installer"] = installer
local provision = require("core.treesitter-install")
local expected = { "lua", "markdown", "markdown_inline" }
assert(vim.deep_equal(provision.languages(), expected), "Languages must be unique and include dependencies")
provision.install(false)
assert(vim.deep_equal(installs[1], expected), "Cold install must include missing parsers")
assert(#waits == 2, "Wait before and after installation")
provision.install(true)
assert(vim.deep_equal(updates[1], expected), "Update all configured parsers and dependencies")
assert(#waits == 4)
timeout = true
local ok, err = pcall(provision.install, true)
assert(not ok and err:find("timed out"))
timeout, fail = false, true
ok, err = pcall(provision.install, true)
assert(not ok and err:find("fixture build failure"))
fail = false
installer.status = {}
installed.lua = false
ok, err = pcall(provision.finish, expected)
assert(not ok and err:find("not installed"), "Missing artifacts must fail even without installer status")

-- Lazy function build hooks must load custom grammar configuration first and
-- bypass ambiguous TSUpdate/TSUpdateSync Ex commands entirely.
local spec = dofile("config/nvim/lua/plugins/treesitter.lua")[1]
local loaded = false
package.loaded["lazy.core.loader"] = {
	load = function(plugin, reason)
		assert(plugin == spec and reason.task == "build")
		loaded = true
	end,
}
provision.install = function(update)
	assert(loaded and update, "Build must load configuration before provisioning")
end
spec.build(spec)
print(
	"treesitter_build_test.lua: ok (cold install, dependencies, update, timeout, failure, missing artifact, build ordering)"
)
