local M = {}

function M.report()
	local lines, healthy = { "OpenCode Neovim Health", "" }, true
	local function check(ok, label, detail)
		healthy = healthy and ok
		table.insert(lines, (ok and "OK   " or "WARN ") .. label .. ": " .. detail)
	end
	check(vim.fn.executable("opencode") == 1, "CLI", "OpenCode V2 on PATH")
	check(vim.fn.executable("bwrap") == 1, "read-only shell", "Bubblewrap on PATH")
	local backend = require("opencode.backend")
	check(vim.fn.filereadable(backend.plugin_path() .. "/index.ts") == 1, "bridge", backend.plugin_path())
	local hook = require("opencode.util").opencode_nvim_hook_path()
	check(vim.fn.filereadable(hook) == 1, "notifications", hook)
	local config, err = require("opencode.tandem").config(vim.fn.getcwd(), true)
	check(config ~= nil, "Tandem", err or "connected; protected launch ready")
	local chat = require("opencode.chat")
	check(vim.env.HERDR_ENV ~= "1" or chat.herdr_available(), "Herdr",
		vim.env.HERDR_ENV == "1" and "managed panes" or "direct terminal fallback")
	for _, session in ipairs(chat.list()) do
		table.insert(lines, string.format("#%s status=%s launch=%s ipc=%s", session.id,
			chat.task_status_label(session), chat.launch_status_label(session), chat.ipc_status_label(session)))
	end
	require("opencode.util").notify(table.concat(lines, "\n"), healthy and vim.log.levels.INFO or vim.log.levels.WARN)
	return healthy
end

return M
