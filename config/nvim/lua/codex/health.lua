local chat = require("codex.chat")
local util = require("codex.util")

local M = {}

local function add_line(lines, ok, label, detail)
	table.insert(lines, string.format("%s %-18s %s", ok and "OK " or "WARN", label, detail))
	return ok
end

local function read_file(path)
	if not path or path == "" or vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	return table.concat(vim.fn.readfile(path), "\n")
end

local function git_root()
	if vim.fs and vim.fs.root then
		return vim.fs.root(vim.fn.getcwd(), { ".git" })
	end

	local git_dir = vim.fs and vim.fs.find(".git", { upward = true, path = vim.fn.getcwd() })[1] or nil
	return git_dir and vim.fn.fnamemodify(git_dir, ":h") or nil
end

local function hook_config_paths()
	local paths = {}
	local seen = {}

	local function add(path)
		if path and path ~= "" and not seen[path] then
			table.insert(paths, path)
			seen[path] = true
		end
	end

	local codex_home = vim.env.CODEX_HOME
	if not codex_home or codex_home == "" then
		codex_home = util.join_path(vim.env.HOME or "~", ".codex")
	end
	add(util.join_path(codex_home, "hooks.json"))

	local root = git_root()
	if root then
		add(util.join_path(util.join_path(root, ".codex"), "hooks.json"))
	end
	add(util.join_path(util.join_path(vim.fn.getcwd(), ".codex"), "hooks.json"))

	return paths
end

local function hook_config_mentions_nvim()
	for _, path in ipairs(hook_config_paths()) do
		local content = read_file(path)
		if content and content:find("codex%-nvim%-hook") then
			return true, path
		end
	end

	return false, nil
end

local function session_summary()
	local sessions = chat.list()
	if #sessions == 0 then
		return "no live chat sessions"
	end

	local parts = {}
	for _, session in ipairs(sessions) do
		table.insert(
			parts,
			string.format(
				"#%s status=%s ipc=%s",
				session.id,
				chat.task_status_label(session),
				chat.ipc_status_label(session)
			)
		)
	end
	return table.concat(parts, ", ")
end

function M.report()
	local lines = { "Codex Neovim Health", "" }
	local ok = true

	ok = add_line(lines, vim.fn.executable("codex") == 1, "codex cli", "codex on PATH") and ok

	local hook_path = util.codex_nvim_hook_path()
	ok = add_line(lines, vim.fn.executable(hook_path) == 1, "nvim hook", hook_path) and ok

	local hook_configured, hook_config_path = hook_config_mentions_nvim()
	ok = add_line(
		lines,
		hook_configured,
		"hook config",
		hook_configured and hook_config_path or "codex-nvim-hook not found in hooks.json"
	) and ok

	add_line(lines, true, "sessions", session_summary())

	util.notify(table.concat(lines, "\n"), ok and vim.log.levels.INFO or vim.log.levels.WARN)
	return ok
end

return M
