local M = {}

M.CODEX_BUF_NAME = "codex://chat"
M.CODEX_CHAT_BUFFERS_BUF_NAME = "codex://chat-buffers"
M.CODEX_CHAT_BUFFERS_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("codex-chat-buffers")
M.CODEX_CHAT_TASK_IDLE_MS = 8000
M.CODEX_TITLE_MODEL = "gpt-5.4-mini"
M.CODEX_TITLE_REASONING_EFFORT = "low"
M.CODEX_JOBS_BUF_NAME = "codex://jobs"
M.CODEX_JOBS_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("codex-jobs")
M.EPHEMERAL_COMMAND_REASONING_EFFORT = "low"
M.EPHEMERAL_RESULT_SUBDIR = "codex/ephemeral"
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
	{ label = "gpt-5.4-mini", model = "gpt-5.4-mini" },
	{ label = "gpt-5.4-nano", model = "gpt-5.4-nano" },
	{ label = "gpt-5.3-codex", model = "gpt-5.3-codex" },
	{ label = "gpt-5.3-codex-spark", model = "gpt-5.3-codex-spark" },
	{ label = "gpt-5.5", model = "gpt-5.5" },
	{ label = "Custom...", custom = true },
}
M.EPHEMERAL_MODEL_TARGETS = {
	{ label = "Ephemeral edits", action = "edit" },
	{ label = "Ephemeral commands", action = "command" },
}
M.VISUAL_BLOCK_MODE = "\022"

return M
