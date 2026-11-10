local M = {}

local function integration_path()
	return vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/../../../"
end

function M.plugin_path()
	return integration_path() .. "pi-extension/index.ts"
end

function M.environment(config)
	local env = {}
	if config and config.tandem then
		local t = config.tandem
		env.TANDEM_ROOT, env.TANDEM_EDITOR, env.TANDEM_BIN = t.root, t.editor, t.command
		if t.state_home then
			env.XDG_STATE_HOME = t.state_home
		end
	end
	return env
end

local function instructions(args, opts)
	local directory = integration_path() .. "opencode-instructions/"
	if opts.text_only then
		vim.list_extend(args, {
			"--no-tools",
			"--no-extensions",
			"--no-mcp",
			"--no-session",
			"--append-system-prompt",
			directory .. "text-only.md",
		})
	else
		vim.list_extend(args, { "--extension", M.plugin_path(), "--append-system-prompt", directory .. "tandem.md" })
		if opts.action == "query" then
			vim.list_extend(args, { "--append-system-prompt", directory .. "analysis.md" })
		end
	end
	if opts.model then
		vim.list_extend(args, { "--model", opts.model })
	end
	return args
end

function M.run_args(opts)
	opts = opts or {}
	local args = instructions({ "pi", "--print", "--mode", "json" }, opts)
	if opts.thread_id then
		vim.list_extend(args, { "--session", opts.thread_id })
	end
	return args
end

function M.interactive_args(session)
	local args = instructions({ "pi" }, session)
	if session.native_session_id then
		vim.list_extend(args, { "--session", session.native_session_id })
	end
	return args
end

-- Print mode emits a session header and complete message_end events as well as
-- token deltas. Consume only finalized messages to avoid duplicated text.
function M.parse_events(lines)
	local session_id, failure
	local texts = {}
	for _, line in ipairs(lines or {}) do
		local ok, event = pcall(vim.json.decode, line)
		if ok and type(event) == "table" then
			if event.type == "session" then
				session_id = event.id
			end
			if event.type == "message_end" and type(event.message) == "table" and event.message.role == "assistant" then
				local message = event.message
				for _, part in ipairs(message.content or {}) do
					if part.type == "text" and type(part.text) == "string" then
						table.insert(texts, part.text)
					end
				end
				if message.stopReason == "error" or message.stopReason == "aborted" then
					failure = message.errorMessage or message.stopReason
				else
					failure = nil -- a successful retry supersedes a transient failure
				end
			elseif event.type == "error" then
				failure = event.message or vim.json.encode(event)
			end
		end
	end
	local answer = #texts > 0 and vim.split(table.concat(texts, "\n\n"), "\n", { plain = true }) or nil
	return session_id, answer, failure
end

return M
