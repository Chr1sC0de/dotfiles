local M = {}
local function backend()
	return require("core.treesitter-backend")
end

function M.languages(selected)
	return backend().languages(selected)
end

function M.finish(languages, timeout)
	backend().wait(languages, timeout or 600000)
	backend().check(languages)
end

-- Pure decision function, also used by the counting-backend regression tests.
function M.plan(mode, installed, artifact, previous, desired, queries, forced)
	if not installed or not artifact then
		return "build", "missing artifact"
	end
	if forced then
		return "build", "forced rebuild"
	end
	if mode == "ensure" then
		return "skip", "already installed"
	end
	if not previous or previous.schema ~= 1 then
		return "build", "untrusted metadata (one-time migration)"
	end
	if previous.fingerprint ~= desired.fingerprint then
		return "build", "changed build inputs"
	end
	if previous.artifact ~= artifact then
		return "build", "artifact changed"
	end
	if previous.queries ~= queries then
		return "queries", "changed query inputs"
	end
	return "skip", "unchanged"
end

function M.run(mode, selected)
	assert(mode == "ensure" or mode == "reconcile" or mode == "rebuild", "Unknown Tree-sitter operation")
	if M._running then
		assert(mode == "ensure", "Tree-sitter reconciliation already running")
		return { built = {}, queries = {}, skipped = {} }
	end
	local b = backend()
	-- Validate arguments before acquiring the lock or modifying artifacts.
	local languages = b.languages(selected)
	if mode == "ensure" and vim.iter(languages):all(b.installed) then
		return { built = {}, queries = {}, skipped = languages }
	end
	local forced = {}
	for _, lang in ipairs(selected or languages) do
		forced[lang] = mode == "rebuild"
	end
	M._running = true
	local locked, unlock = pcall(b.lock, 600000)
	if not locked then
		M._running = false
		error(unlock)
	end
	local summary = { built = {}, queries = {}, skipped = {} }
	local ok, err = xpcall(function()
		b.wait(languages, 600000)
		-- Resolve all sources before changing artifacts. A remote-resolution error
		-- must not leave a half-applied update or remove working parsers.
		local desired = {}
		for _, lang in ipairs(languages) do
			if mode ~= "ensure" or not b.installed(lang) then
				desired[lang] = b.desired(lang)
			end
		end
		local records = {}
		for _, lang in ipairs(languages) do
			local inputs = desired[lang]
			local action, reason
			if mode == "ensure" and b.installed(lang) then
				action, reason = "skip", "already installed"
			else
				action, reason = M.plan(
					mode,
					b.installed(lang),
					b.artifact(lang),
					b.read(lang),
					inputs,
					b.query_identity(lang, inputs),
					forced[lang]
				)
			end
			if mode ~= "ensure" or action ~= "skip" then
				b.report(lang, reason)
			end
			if action == "build" then
				b.build(lang, inputs)
				b.validate(lang, true)
				-- Track parser success separately: a query failure must not force
				-- a successful parser compilation to run again on retry.
				b.write(lang, {
					schema = 1,
					fingerprint = inputs.fingerprint,
					commit = inputs.commit,
					artifact = b.artifact(lang),
				})
				table.insert(summary.built, lang)
			elseif action == "queries" then
				b.refresh_queries(lang, inputs)
				table.insert(summary.queries, lang)
			else
				table.insert(summary.skipped, lang)
			end
			if action ~= "skip" then
				records[lang] = inputs
			end
		end
		b.check(languages)
		-- Validate after all dependencies are built; inherited queries may refer
		-- to parsers that did not exist at the beginning of a cold install.
		for _, lang in ipairs(languages) do
			if mode ~= "ensure" or records[lang] then
				b.validate(lang)
			end
		end
		for lang, inputs in pairs(records) do
			b.write(lang, {
				schema = 1,
				fingerprint = inputs.fingerprint,
				commit = inputs.commit,
				artifact = b.artifact(lang),
				queries = b.query_identity(lang, inputs),
			})
		end
	end, debug.traceback)
	M._running = false
	local unlocked, unlock_error = pcall(unlock)
	assert(unlocked, unlock_error)
	assert(ok, err)
	return summary
end

-- Compatibility for callers outside the Lazy hook.
function M.install(update)
	M.run(update and "reconcile" or "ensure")
	return M.languages()
end

function M.setup_commands()
	require("core.treesitter-background").setup_commands()
	local function register(name, mode)
		vim.api.nvim_create_user_command(name, function(opts)
			require("core.treesitter-background").start(mode, #opts.fargs > 0 and opts.fargs or nil)
		end, {
			nargs = "*",
			force = true,
			complete = function()
				return M.languages()
			end,
		})
	end
	register("DotfilesTSUpdate", "reconcile")
	register("DotfilesTSRebuild", "rebuild")
end

return M
