local M = {}

M.CODEX_BUF_NAME = "codex://chat"
M.CODEX_CHAT_BUFFERS_BUF_NAME = "codex://chat-buffers"
M.CODEX_CHAT_BUFFERS_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("codex-chat-buffers")
M.CODEX_CHAT_TASK_IDLE_MS = 8000
M.CODEX_TITLE_MODEL = "gpt-6-astra"
M.CODEX_TITLE_REASONING_EFFORT = "low"
M.CODEX_JOBS_BUF_NAME = "codex://jobs"
M.CODEX_JOBS_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("codex-jobs")
M.EPHEMERAL_COMMAND_REASONING_EFFORT = "low"
M.EPHEMERAL_DIAGNOSTIC_NAMESPACE = vim.api.nvim_create_namespace("codex-ephemeral")
M.EPHEMERAL_SPINNER_NAMESPACE = vim.api.nvim_create_namespace("codex-ephemeral-spinner")
M.EPHEMERAL_RECENT_JOB_LIMIT = 20
M.EPHEMERAL_SIGN_GROUP = "codex-ephemeral"
M.EPHEMERAL_SPINNER_STYLES = {
	edit = {
		highlight = "DiagnosticWarn",
		verb = "editing",
		frames = {
			{ name = "CodexEphemeralEditSpinner1", text = "󰚩" },
			{ name = "CodexEphemeralEditSpinner2", text = "󰏫" },
			{ name = "CodexEphemeralEditSpinner3", text = "󰚩" },
			{ name = "CodexEphemeralEditSpinner4", text = "󰏬" },
		},
	},
	command = {
		highlight = "DiagnosticInfo",
		verb = "command over",
		frames = {
			{ name = "CodexEphemeralCommandSpinner1", text = "󰚩" },
			{ name = "CodexEphemeralCommandSpinner2", text = "" },
			{ name = "CodexEphemeralCommandSpinner3", text = "󰚩" },
			{ name = "CodexEphemeralCommandSpinner4", text = "" },
		},
	},
}
M.EPHEMERAL_MODEL_CHOICES = {
	{ label = "CLI default", model = nil },
	{ label = "Astra", model = "gpt-6-astra" },
	{ label = "5.6 Sol", model = "gpt-5.6-sol" },
	{ label = "5.6 Terra", model = "gpt-5.6-terra" },
	{ label = "5.6 Luna", model = "gpt-5.6-luna" },
	{ label = "5.3 Codex Spark", model = "gpt-5.3-codex-spark" },
	{ label = "Custom...", custom = true },
}
M.EPHEMERAL_MODEL_TARGETS = {
	{ label = "Ephemeral edits", action = "edit" },
	{ label = "Ephemeral commands", action = "command" },
}
M.VISUAL_BLOCK_MODE = "\022"

return M
