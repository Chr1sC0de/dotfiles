local M = {}

-- Include query/parser dependencies (for example markdown_inline) in completion
-- checks: the manager's wait() only checks the languages explicitly passed in.
function M.languages()
	local util = require("tree-sitter-manager.util")
	local languages, seen = {}, {}
	local function add(language)
		if seen[language] then
			return
		end
		seen[language] = true
		table.insert(languages, language)
		for _, dependency in ipairs(util.get_requires(language)) do
			add(dependency)
		end
	end
	for _, language in ipairs(require("tree-sitter-manager.config").cfg.ensure_installed) do
		add(language)
	end
	return languages
end

function M.finish(languages, timeout)
	local installer = require("tree-sitter-manager.installer")
	local util = require("tree-sitter-manager.util")
	assert(installer.wait(languages, timeout or 600000), "Tree-sitter installation timed out")
	local failures = {}
	for _, language in ipairs(languages) do
		local status = installer.status[language]
		if (status and not status.ok) or not util.is_installed(language) then
			table.insert(failures, language .. ": " .. (status and status.error or "not installed"))
		end
	end
	assert(#failures == 0, "Tree-sitter installation failed:\n" .. table.concat(failures, "\n"))
end

function M.install(update)
	local languages = M.languages()
	local installer = require("tree-sitter-manager.installer")
	-- setup() may already be installing missing parsers. Finish those jobs before
	-- update() removes artifacts, avoiding concurrent builds of the same parser.
	assert(installer.wait(languages, 600000), "Tree-sitter installation timed out")
	if update then
		installer.update(languages)
	else
		installer.install(languages)
	end
	M.finish(languages)
	return languages
end

return M
