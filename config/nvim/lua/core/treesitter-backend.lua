-- Narrow adapter for the locked tree-sitter-manager API. Compilation stays in
-- the manager; this module supplies immutable source identities and state I/O.
local M = {}
local uv = vim.uv
local root = vim.fn.stdpath("state") .. "/dotfiles-treesitter-v1"
local validator = debug.getinfo(1, "S").source:sub(2):gsub("treesitter%-backend.lua$", "treesitter-validate.lua")

local function hash_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return vim.fn.sha256(content)
end

local function command(argv)
	local result = vim.system(argv, { text = true }):wait(120000)
	assert(result.code == 0, table.concat(argv, " ") .. ": " .. (result.stderr or "command failed"))
	return vim.trim(result.stdout)
end

function M.lock(timeout)
	vim.fn.mkdir(root, "p")
	local lock = root .. "/lock"
	local acquired = vim.wait(timeout, function()
		if uv.fs_mkdir(lock, 448) then
			local wrote, err = pcall(vim.fn.writefile, { tostring(vim.fn.getpid()) }, lock .. "/pid")
			if not wrote then
				vim.fn.delete(lock, "rf")
				error(err)
			end
			return true
		end
		-- A killed Neovim must not permanently prevent future updates.
		local ok, lines = pcall(vim.fn.readfile, lock .. "/pid")
		local pid = ok and tonumber(lines[1])
		local stat = uv.fs_stat(lock)
		local abandoned = not pid and stat and os.time() - stat.mtime.sec > 30
		if abandoned or (pid and not uv.kill(pid, 0)) then
			vim.fn.delete(lock, "rf")
		end
		return false
	end, 100)
	assert(acquired, "Timed out waiting for Tree-sitter lock: " .. lock)
	return function()
		vim.fn.delete(lock, "rf")
	end
end

function M.languages(selected)
	local config = require("tree-sitter-manager.config")
	local util = require("tree-sitter-manager.util")
	local result, seen = {}, {}
	local function add(lang)
		assert(
			type(lang) == "string" and lang:match("^[%w_]+$") and config.effective_repos[lang],
			"Unknown Tree-sitter language: " .. tostring(lang)
		)
		if seen[lang] then
			return
		end
		seen[lang] = true
		for _, dependency in ipairs(util.get_requires(lang)) do
			add(dependency)
		end
		-- Build dependencies first: the manager auto-installs missing requires.
		-- This avoids implicitly building one and then migrating it a second time.
		table.insert(result, lang)
	end
	for _, lang in ipairs(selected or config.cfg.ensure_installed) do
		add(lang)
	end
	return result
end

function M.installed(lang)
	return require("tree-sitter-manager.util").is_installed(lang) == true
end

function M.artifact(lang)
	local util = require("tree-sitter-manager.util")
	return util.is_only_query(lang) and "query-only" or hash_file(util.ppath(lang))
end

function M.read(lang)
	local path = root .. "/" .. lang .. ".json"
	local ok, record = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
	end)
	return ok and type(record) == "table" and record.schema == 1 and record or nil
end

function M.write(lang, record)
	local path = root .. "/" .. lang .. ".json"
	local temporary = path .. "." .. vim.fn.getpid() .. ".tmp"
	vim.fn.writefile({ vim.json.encode(record) }, temporary)
	assert(uv.fs_rename(temporary, path))
end

function M.query_identity(lang, desired)
	local files = vim.fn.globpath(vim.o.runtimepath, "queries/" .. lang .. "/*.scm", true, true)
	-- Include source queries when the destination is absent or is a fallback copy.
	local util = require("tree-sitter-manager.util")
	vim.list_extend(files, vim.fn.glob(util.PLUGIN_ROOT .. "/runtime/queries/" .. lang .. "/*.scm", true, true))
	table.sort(files)
	local values = { (desired and desired.info or util.get_repo_info(lang) or {}).queries or "manager-queries" }
	for _, path in ipairs(files) do
		table.insert(values, path .. ":" .. (hash_file(path) or "missing"))
	end
	return vim.fn.sha256(table.concat(values, "\n"))
end

function M.desired(lang)
	local util = require("tree-sitter-manager.util")
	local info = vim.deepcopy(util.get_repo_info(lang) or {})
	local commit = info.revision
	if info.url and (not commit or not (#commit == 40 and commit:match("^%x+$"))) then
		local ref = commit or info.branch or "HEAD"
		local output = command({ "git", "ls-remote", info.url, ref, ref .. "^{}" })
		local resolved, peeled
		for sha, name in output:gmatch("(%x+)%s+([^\n]+)") do
			resolved = resolved or sha
			if name:match("%^{}$") then
				peeled = sha
			end
		end
		commit = peeled or resolved
		assert(commit and #commit == 40, "Cannot resolve immutable source for " .. lang .. ": " .. ref)
	end
	local platform = uv.os_uname()
	local compiler = vim.env.CC or "cc"
	local cxx = vim.env.CXX or "c++"
	local build = {
		info.url or "query-only",
		commit or "",
		info.location or "",
		tostring(info.generate),
		command({ "tree-sitter", "--version" }),
		compiler,
		command({ compiler, "--version" }),
		vim.env.CFLAGS or "",
		cxx,
		command({ cxx, "--version" }),
		vim.env.CXXFLAGS or "",
		util.ppath(lang),
		platform.sysname,
		platform.machine,
		tostring(vim.treesitter.language_version),
		tostring(vim.treesitter.minimum_language_version),
	}
	return { fingerprint = vim.fn.sha256(table.concat(build, "\n")), commit = commit, info = info }
end

function M.wait(languages, timeout)
	assert(require("tree-sitter-manager.installer").wait(languages, timeout), "Tree-sitter installation timed out")
end

function M.check(languages)
	local installer = require("tree-sitter-manager.installer")
	for _, lang in ipairs(languages) do
		local status = installer.status[lang]
		assert(not status or status.ok, lang .. ": " .. tostring(status and status.error))
		assert(M.installed(lang), "Tree-sitter artifact missing: " .. lang)
	end
end

function M.build(lang, desired)
	local config = require("tree-sitter-manager.config")
	local original = config.effective_repos[lang]
	local entry = type(original) == "table" and vim.deepcopy(original) or { install_info = { url = original } }
	entry.install_info = vim.tbl_extend("force", desired.info, { revision = desired.commit })
	config.effective_repos[lang] = entry
	local ok, err = xpcall(function()
		require("tree-sitter-manager.installer").update({ lang })
		M.wait({ lang }, 600000)
		M.check({ lang })
	end, debug.traceback)
	config.effective_repos[lang] = original
	assert(ok, err)
end

function M.refresh_queries(lang, desired)
	local util = require("tree-sitter-manager.util")
	local info = desired.info
	local target = util.qpath(lang)
	local source = util.PLUGIN_ROOT .. "/runtime/queries/" .. lang
	local temporary
	local ok, err = xpcall(function()
		if info.queries then
			-- The backend does not retain checkouts. Fetch only when query inputs
			-- changed, and always check out the already resolved immutable commit.
			temporary = vim.fn.tempname()
			command({ "git", "init", "--quiet", temporary })
			command({ "git", "-C", temporary, "remote", "add", "origin", info.url })
			command({ "git", "-C", temporary, "fetch", "--quiet", "--depth=1", "origin", desired.commit })
			command({ "git", "-C", temporary, "checkout", "--quiet", "--detach", "FETCH_HEAD" })
			source = vim.fs.joinpath(temporary, info.location or "", info.queries)
		end
		assert(uv.fs_stat(source), "Missing query source for " .. lang .. ": " .. source)
		if not info.queries and uv.fs_realpath(target) == uv.fs_realpath(source) then
			return -- live symlink already sees the changed manager query files
		end
		local staged = target .. "." .. vim.fn.getpid() .. ".tmp"
		vim.fn.delete(staged, "rf")
		local result = util.copy_dir(source, staged)
		assert(result.ok, result.error)
		vim.fn.delete(target, "rf")
		assert(uv.fs_rename(staged, target))
	end, debug.traceback)
	if temporary then
		vim.fn.delete(temporary, "rf")
	end
	assert(ok, err)
	vim.treesitter.query.get:clear()
end

function M.validate(lang, parser_only)
	if require("tree-sitter-manager.util").is_only_query(lang) then
		return
	end
	command({
		vim.v.progpath,
		"--headless",
		"-u",
		"NONE",
		"-i",
		"NONE",
		"-n",
		"-l",
		validator,
		lang,
		require("tree-sitter-manager.util").ppath(lang),
		vim.json.encode(vim.opt.runtimepath:get()),
		parser_only and "parser" or "queries",
	})
end

function M.report(lang, reason)
	print("Tree-sitter " .. lang .. ": " .. reason)
end

return M
