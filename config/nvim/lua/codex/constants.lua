local M = {}

M.CODEX_BUF_NAME = "codex://chat"
M.CODEX_CHAT_BUFFERS_BUF_NAME = "codex://chat-buffers"
M.CODEX_CHAT_BUFFERS_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("codex-chat-buffers")
M.CODEX_CHAT_TASK_IDLE_MS = 8000
M.CODEX_TITLE_MODEL = "gpt-6-astra"
M.CODEX_TITLE_REASONING_EFFORT = "low"
M.CODEX_JOBS_BUF_NAME = "codex://jobs"
M.CODEX_JOBS_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("codex-jobs")
M.EPHEMERAL_QUERY_REASONING_EFFORT = "low"
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
	query = {
		highlight = "DiagnosticInfo",
		verb = "querying",
		frames = {
			{ name = "CodexEphemeralQuerySpinner1", text = "󰚩" },
			{ name = "CodexEphemeralQuerySpinner2", text = "" },
			{ name = "CodexEphemeralQuerySpinner3", text = "󰚩" },
			{ name = "CodexEphemeralQuerySpinner4", text = "" },
		},
	},
}
M.EPHEMERAL_MODEL_TARGETS = {
	{ label = "Edits (file changes)", action = "edit" },
	{ label = "Queries (read-only)", action = "query" },
}
M.VISUAL_BLOCK_MODE = "\022"

return M
