local M = {}

function M.report()
	local lines, healthy = { "Agent Neovim Health", "" }, true
	local function check(ok, label, detail)
		healthy = healthy and ok
		table.insert(lines, (ok and "OK   " or "WARN ") .. label .. ": " .. detail)
	end
	local selected = require("agents.selection").get()
	check(vim.fn.executable(selected) == 1, "CLI", selected .. " (selected backend)")
	local backend = require("agents.backend")
	check(vim.fn.filereadable(backend.plugin_path() .. "/index.ts") == 1, "bridge", backend.plugin_path())
	check(vim.fn.filereadable(backend.get("pi").plugin_path()) == 1, "Pi bridge", backend.get("pi").plugin_path())
	local hook = require("agents.util").opencode_nvim_hook_path()
	check(vim.fn.filereadable(hook) == 1, "notifications", hook)
	local config, err = require("agents.tandem").config(vim.fn.getcwd(), true)
	check(config ~= nil, "Tandem", err or "RPC editor registered; CLI launch ready")
	local chat = require("agents.chat")
	check(
		vim.env.HERDR_ENV ~= "1" or chat.herdr_available(),
		"Herdr",
		vim.env.HERDR_ENV == "1" and "managed panes" or "direct terminal fallback"
	)
	for _, session in ipairs(chat.list()) do
		table.insert(
			lines,
			string.format(
				"[%s] #%s status=%s launch=%s ipc=%s",
				session.backend or "opencode",
				session.id,
				chat.task_status_label(session),
				chat.launch_status_label(session),
				chat.ipc_status_label(session)
			)
		)
	end
	require("agents.util").notify(table.concat(lines, "\n"), healthy and vim.log.levels.INFO or vim.log.levels.WARN)
	return healthy
end

return M
