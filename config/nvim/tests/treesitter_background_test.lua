-- Run: nvim --headless -u NONE -i NONE -n -l config/nvim/tests/treesitter_background_test.lua
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/lua/core", "p")
vim.fn.mkdir(root .. "/lua/tree-sitter-manager", "p")
vim.env.XDG_STATE_HOME = root .. "/state"
vim.env.TS_TEST_ROOT = root
local source = vim.fn.getcwd() .. "/config/nvim"
local function file(path, text)
	vim.fn.writefile(vim.split(text, "\n"), root .. "/lua/" .. path)
end
file(
	"tree-sitter-manager/config.lua",
	[[
return { cfg = { ensure_installed = { "lua" }, auto_install = false, highlight = false, nohighlight = {} },
 effective_repos = { lua = { install_info = { revision = "pinned-test-revision" } } } }
]]
)
file(
	"tree-sitter-manager.lua",
	[[
return { setup = function(opts)
 assert(#opts.ensure_installed == 0 and opts.auto_install == false, "Worker setup must not auto-install")
 require("tree-sitter-manager.config").cfg = opts
end }
]]
)
file(
	"core/treesitter-backend.lua",
	([=[
local root = vim.env.TS_TEST_ROOT
local real = dofile(%q)
local b = { lock = real.lock }
function b.languages(selected)
 for _, lang in ipairs(selected or {}) do assert(lang == "lua", "Unknown language") end
 return selected or { "lua" }
end
function b.installed() return vim.uv.fs_stat(root .. "/artifact") ~= nil end
function b.artifact() return b.installed() and "artifact" end
function b.read()
 if vim.uv.fs_stat(root .. "/record") then
  return { schema = 1, fingerprint = "v1", artifact = "artifact", queries = "q1" }
 end
end
function b.write() vim.fn.writefile({ "ok" }, root .. "/record") end
function b.query_identity() return "q1" end
function b.desired()
 assert(require("tree-sitter-manager.config").effective_repos.lua.install_info.revision == "pinned-test-revision")
 return { fingerprint = "v1" }
end
function b.wait() end
function b.check() assert(b.installed(), "missing artifact") end
function b.build()
 -- Deliberately block the child, not the parent's event loop.
 vim.system({ "sleep", "0.4" }):wait()
 assert(not vim.uv.fs_stat(root .. "/fail"), "fixture build failure")
 vim.fn.writefile({ "build" }, root .. "/builds", "a")
 vim.fn.writefile({ "ok" }, root .. "/artifact")
end
function b.validate() end
function b.report(lang, reason) print(lang .. ": " .. reason) end
return b
]=]):format(source .. "/lua/core/treesitter-backend.lua")
)
vim.opt.runtimepath:prepend(source)
vim.opt.runtimepath:prepend(root)
-- Use the real Lazy scheduler without loading the user's init.lua.
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
local messages = {}
vim.notify = function(message, level)
	table.insert(messages, { message, level })
end
local bg = require("core.treesitter-background")
local function wait(job)
	assert(
		vim.wait(5000, function()
			return job.done
		end, 10),
		"worker timeout"
	)
	return job.code
end
local start = vim.uv.hrtime()
local first = bg.start("ensure")
assert((vim.uv.hrtime() - start) / 1e6 < 250, "Launcher must return before slow work finishes")
assert(not first.done)
assert(bg.start("ensure") == first, "Coalesce startup requests")
assert(not pcall(bg.start, "rebuild"), "Explicit requests must not silently disappear")
local edited = false
vim.defer_fn(function()
	assert(not first.done, "Must edit during compilation")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "editing during install" })
	edited = true
end, 50)
-- A second editor's startup worker must reuse artifacts after taking the lock.
package.loaded["core.treesitter-background"] = nil
local second_bg = require("core.treesitter-background")
local second = second_bg.start("ensure")
assert(wait(first) == 0 and wait(second) == 0)
assert(edited and vim.api.nvim_get_current_line() == "editing during install")
assert(#vim.fn.readfile(root .. "/builds") == 1, "Concurrent workers must not compile twice")
assert(vim.fn.readfile(first.log)[1] == "Tree-sitter worker: ensure")
assert(bg.start("ensure").done, "Warm startup must not spawn")
assert(bg.active == first)
assert(not pcall(bg.start, "ensure", { "bad" }), "Validate selections before launch")

vim.fn.writefile({ "fail" }, root .. "/fail")
assert(wait(bg.start("rebuild")) ~= 0)
assert(table.concat(vim.fn.readfile(bg.log), "\n"):find("fixture build failure", 1, true))
vim.fn.delete(root .. "/fail")
assert(wait(bg.start("rebuild")) == 0, "Failure must release lock for retry")

local async = require("lazy.async")
vim.fn.delete(root .. "/artifact")
local startup = bg.start("ensure") -- Lazy must wait for an earlier startup job.
local finished, failure = false, nil
local task = async
	.new(function()
		bg.build()
		finished = true
	end)
	:on("error", function(err)
		failure = err
	end)
assert(vim.wait(5000, function()
	return not task:running()
end, 10))
assert(finished and not failure and startup.done, tostring(failure))
-- Lazy also receives nonzero worker exits, rather than marking them successful.
vim.fn.writefile({ "fail" }, root .. "/fail")
vim.fn.delete(root .. "/artifact")
finished, failure = false, nil
local ticks = 0
local timer = vim.uv.new_timer()
timer:start(
	10,
	10,
	vim.schedule_wrap(function()
		ticks = ticks + 1
	end)
)
task = async
	.new(function()
		bg.build()
		finished = true
	end)
	:on("error", function(err)
		failure = err
	end)
assert(vim.wait(5000, function()
	return not task:running()
end, 10))
timer:stop()
timer:close()
assert(not finished and failure and ticks > 5, "Lazy must yield and propagate failures")
-- Detached workers must finish even when their launching editor exits.
vim.fn.delete(root .. "/fail")
vim.fn.writefile({
	"vim.opt.runtimepath = " .. vim.inspect(vim.opt.runtimepath:get()),
	"require('core.treesitter-background').start('ensure')",
	"vim.cmd('qa!')",
}, root .. "/launch.lua")
local parent =
	vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", root .. "/launch.lua" })
		:wait(5000)
assert(parent.code == 0, parent.stderr)
assert(
	vim.wait(5000, function()
		return vim.uv.fs_stat(root .. "/artifact")
			and not vim.uv.fs_stat(vim.fn.stdpath("state") .. "/dotfiles-treesitter-v1/lock")
	end, 20),
	"Detached worker did not finish after editor exit"
)
vim.fn.delete(root, "rf")
print(
	"treesitter_background_test.lua: ok (real worker, responsive edits, snapshot, concurrent workers, warm no-op, failure/retry, Lazy completion/errors)"
)
