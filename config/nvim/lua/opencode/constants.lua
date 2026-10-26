local M = {}

M.OPENCODE_BUF_NAME = "opencode://chat"
M.OPENCODE_CHAT_BUFFERS_BUF_NAME = "opencode://chat-buffers"
M.OPENCODE_CHAT_BUFFERS_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("opencode-chat-buffers")
M.OPENCODE_CHAT_TASK_IDLE_MS = 8000
M.OPENCODE_TITLE_MODEL = nil -- Follow the configured OpenCode model.
M.OPENCODE_JOBS_BUF_NAME = "opencode://jobs"
M.OPENCODE_JOBS_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("opencode-jobs")
M.EPHEMERAL_QUERY_REASONING_EFFORT = nil -- Select provider/model#variant in the model picker.
M.EPHEMERAL_DIAGNOSTIC_NAMESPACE = vim.api.nvim_create_namespace("opencode-ephemeral")
M.EPHEMERAL_SPINNER_NAMESPACE = vim.api.nvim_create_namespace("opencode-ephemeral-spinner")
M.EPHEMERAL_RECENT_JOB_LIMIT = 20
M.EPHEMERAL_SIGN_GROUP = "opencode-ephemeral"
M.EPHEMERAL_SPINNER_STYLES = {
	edit = {
		highlight = "DiagnosticWarn",
		verb = "editing",
		frames = {
			{ name = "OpenCodeEphemeralEditSpinner1", text = "󰚩" },
			{ name = "OpenCodeEphemeralEditSpinner2", text = "󰏫" },
			{ name = "OpenCodeEphemeralEditSpinner3", text = "󰚩" },
			{ name = "OpenCodeEphemeralEditSpinner4", text = "󰏬" },
		},
	},
	query = {
		highlight = "DiagnosticInfo",
		verb = "querying",
		frames = {
			{ name = "OpenCodeEphemeralQuerySpinner1", text = "󰚩" },
			{ name = "OpenCodeEphemeralQuerySpinner2", text = "" },
			{ name = "OpenCodeEphemeralQuerySpinner3", text = "󰚩" },
			{ name = "OpenCodeEphemeralQuerySpinner4", text = "" },
		},
	},
}
M.EPHEMERAL_MODEL_TARGETS = {
	{ label = "Edits (file changes)", action = "edit" },
	{ label = "Queries (read-only)", action = "query" },
	{ label = "Commit message", action = "commit" },
}
M.VISUAL_BLOCK_MODE = "\022"

return M
