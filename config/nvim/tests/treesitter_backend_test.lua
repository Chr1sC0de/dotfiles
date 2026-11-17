-- Run: nvim --headless -u NONE -i NONE -n -l config/nvim/tests/treesitter_backend_test.lua
local base = vim.fn.getcwd() .. "/config/nvim"
vim.opt.runtimepath:prepend(base)
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.env.XDG_STATE_HOME = temporary .. "/state"
local source, target = temporary .. "/manager/runtime/queries/lua", temporary .. "/site/queries/lua"
local artifact = temporary .. "/lua.so"
vim.fn.mkdir(source, "p")
vim.fn.mkdir(vim.fn.fnamemodify(target, ":h"), "p")
vim.fn.writefile({ "(identifier) @variable" }, source .. "/highlights.scm")
local info = { url = "https://example.invalid/grammar", revision = string.rep("a", 40), location = "." }
local function copy_dir(from, to)
	vim.fn.mkdir(to, "p")
	for name in vim.fs.dir(from) do
		assert(vim.uv.fs_copyfile(from .. "/" .. name, to .. "/" .. name))
	end
	return { ok = true }
end
package.loaded["tree-sitter-manager.util"] = {
	PLUGIN_ROOT = temporary .. "/manager",
	get_repo_info = function()
		return vim.deepcopy(info)
	end,
	get_requires = function(lang)
		return lang == "markdown" and { "lua" } or {}
	end,
	is_only_query = function()
		return false
	end,
	is_installed = function()
		return vim.uv.fs_stat(artifact) ~= nil
	end,
	ppath = function()
		return artifact
	end,
	qpath = function()
		return target
	end,
	copy_dir = copy_dir,
}
package.loaded["tree-sitter-manager.config"] = {
	cfg = { ensure_installed = { "markdown", "lua" } },
	effective_repos = { markdown = {}, lua = {} },
}
local backend = require("core.treesitter-backend")
assert(vim.deep_equal(backend.languages(), { "lua", "markdown" }), "Dependencies must precede parents")
assert(not pcall(backend.languages, { "../invalid" }))
local unlock = backend.lock(1000)
backend.write("lua", { schema = 1, fingerprint = "fixture" })
assert(backend.read("lua").fingerprint == "fixture")
local state = vim.fn.stdpath("state") .. "/dotfiles-treesitter-v1"
vim.fn.writefile({ "not json" }, state .. "/lua.json")
assert(backend.read("lua") == nil)
backend.write("lua", { schema = 999 })
assert(backend.read("lua") == nil)

-- A second real Neovim process must not acquire or delete our live lock.
local child = temporary .. "/lock-probe.lua"
vim.fn.writefile({
	("vim.opt.runtimepath:prepend(%q)"):format(base),
	"local ok, release = pcall(require('core.treesitter-backend').lock, 200)",
	"if ok then release(); os.exit(2) end",
}, child)
local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", child }, { text = true })
	:wait(10000)
assert(result.code == 0, result.stderr)
assert(vim.uv.fs_stat(state .. "/lock"), "Contender must not remove a live lock")
unlock()
vim.fn.mkdir(state .. "/lock")
vim.fn.writefile({ "999999999" }, state .. "/lock/pid")
unlock = backend.lock(1000)
unlock()
-- A crash between mkdir and writing the owner file must also be recoverable.
vim.fn.mkdir(state .. "/lock")
assert(vim.uv.fs_utime(state .. "/lock", os.time() - 60, os.time() - 60))
unlock = backend.lock(1000)
unlock()

assert(backend.artifact("lua") == nil)
vim.fn.writefile({ "first artifact" }, artifact)
local hash = backend.artifact("lua")
vim.fn.writefile({ "corrupt artifact" }, artifact)
assert(backend.artifact("lua") ~= hash)
local before = backend.query_identity("lua")
vim.fn.writefile({ "(identifier) @string" }, source .. "/highlights.scm")
assert(backend.query_identity("lua") ~= before)
backend.refresh_queries("lua", { info = info })
assert(vim.fn.readfile(target .. "/highlights.scm")[1] == "(identifier) @string")
vim.fn.delete(target, "rf")
backend.refresh_queries("lua", { info = info })
assert(vim.uv.fs_stat(target .. "/highlights.scm"), "Repair missing queries without compilation")

local system = vim.system
local git_calls = 0
vim.system = function(argv)
	local output = "fixture toolchain"
	if argv[1] == "git" then
		git_calls = git_calls + 1
		output = string.rep("b", 40) .. "\trefs/tags/v1\n" .. string.rep("c", 40) .. "\trefs/tags/v1^{}\n"
	end
	return {
		wait = function()
			return { code = 0, stdout = output, stderr = "" }
		end,
	}
end
local pinned = backend.desired("lua")
assert(pinned.commit == string.rep("a", 40) and git_calls == 0, "Immutable pins need no network lookup")
info.revision = "v1"
assert(backend.desired("lua").commit == string.rep("c", 40), "Use peeled annotated tag commit")
vim.system = system

-- The adapter must override the moving source with the exact resolved commit
-- only for the build, and restore manager configuration even after failure.
local config = require("tree-sitter-manager.config")
local original = config.effective_repos.lua
local build_fails = false
package.loaded["tree-sitter-manager.installer"] = {
	status = { lua = { ok = true } },
	wait = function()
		return true
	end,
	update = function(languages)
		assert(vim.deep_equal(languages, { "lua" }))
		assert(config.effective_repos.lua.install_info.revision == pinned.commit)
		assert(not build_fails, "fixture backend compilation failed")
	end,
}
backend.build("lua", pinned)
assert(config.effective_repos.lua == original)
build_fails = true
assert(not pcall(backend.build, "lua", pinned))
assert(config.effective_repos.lua == original)
assert(not pcall(backend.validate, "lua", true), "Fresh child must reject an invalid library")

-- A local Git fixture exercises grammar-owned query refresh without compiling.
local repo = temporary .. "/grammar"
vim.fn.mkdir(repo .. "/queries", "p")
vim.fn.writefile({ "(identifier) @constant" }, repo .. "/queries/highlights.scm")
local function git(args)
	local argv = { "git", "-C", repo }
	vim.list_extend(argv, args)
	local result = vim.system(argv, { text = true }):wait(10000)
	assert(result.code == 0, result.stderr)
	return vim.trim(result.stdout)
end
git({ "init", "--quiet" })
git({ "add", "." })
git({ "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture" })
local desired_queries =
	{ commit = git({ "rev-parse", "HEAD" }), info = { url = repo, location = ".", queries = "queries" } }
local parser_hash = backend.artifact("lua")
backend.refresh_queries("lua", desired_queries)
assert(vim.fn.readfile(target .. "/highlights.scm")[1] == "(identifier) @constant")
assert(backend.artifact("lua") == parser_hash, "Query-only refresh must not modify the parser")
vim.fn.delete(temporary, "rf")
print(
	"treesitter_backend_test.lua: ok (atomic state, corrupt manifests, real cross-process lock, stale lock, artifact hashes, query refresh, topological order, immutable revisions)"
)
