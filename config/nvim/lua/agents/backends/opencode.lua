-- OpenCode V2 private-server launch configuration.
local M = {}

function M.plugin_path()
	return vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/../../../opencode-plugin"
end

function M.environment(config, opts)
	opts = opts or {}
	local inherited = {}
	if vim.env.OPENCODE_CONFIG_CONTENT and vim.env.OPENCODE_CONFIG_CONTENT ~= "" then
		local ok, decoded = pcall(vim.json.decode, vim.env.OPENCODE_CONFIG_CONTENT)
		if not ok or type(decoded) ~= "table" then
			return nil, "OPENCODE_CONFIG_CONTENT is not valid JSON"
		end
		inherited = decoded
	end
	local merged = vim.tbl_deep_extend("force", inherited, config or {})
	merged.tandem = nil
	merged.instructions = vim.deepcopy(merged.instructions or {})
	local instructions = M.plugin_path() .. "/../opencode-instructions/"
	if opts.text_only then
		merged.policies = vim.deepcopy(merged.policies or {})
		table.insert(merged.policies, { action = "tool.use", resource = "*", effect = "deny" })
		table.insert(merged.instructions, instructions .. "text-only.md")
	else
		merged.permissions = vim.deepcopy(merged.permissions or {})
		table.insert(merged.permissions, { action = "*", resource = "*", effect = "allow" })
		merged.plugins = vim.deepcopy(merged.plugins or {})
		table.insert(merged.plugins, { package = M.plugin_path() })
		if config and config.tandem then
			table.insert(merged.instructions, instructions .. "tandem.md")
		end
		if opts.read_only then
			table.insert(merged.instructions, instructions .. "analysis.md")
		end
	end
	local env = { OPENCODE_CONFIG_CONTENT = vim.json.encode(merged) }
	if config and config.tandem then
		env.TANDEM_ROOT, env.TANDEM_EDITOR, env.TANDEM_BIN =
			config.tandem.root, config.tandem.editor, config.tandem.command
		if config.tandem.state_home then
			env.XDG_STATE_HOME = config.tandem.state_home
		end
	end
	return env
end

function M.interactive_args(session)
	local args = { "opencode", "--standalone", session.cwd }
	if session.native_session_id then
		vim.list_extend(args, { "--session", session.native_session_id })
	end
	return args
end

function M.run_args(opts)
	opts = opts or {}
	local args = { "opencode", "run", "--standalone", "--format", "json" }
	if opts.model then
		vim.list_extend(args, { "--model", opts.model })
	end
	if opts.thread_id then
		vim.list_extend(args, { "--session", opts.thread_id })
	end
	return args
end

function M.parse_events(lines)
	local session_id, answer, failure
	local texts = {}
	for _, line in ipairs(lines or {}) do
		local ok, event = pcall(vim.json.decode, line)
		if ok and type(event) == "table" then
			if type(event.sessionID) == "string" then
				session_id = event.sessionID
			end
			if event.type == "text" and type(event.part) == "table" and type(event.part.text) == "string" then
				table.insert(texts, event.part.text)
			elseif event.type == "error" then
				failure = vim.json.encode(event.error or event)
			end
		end
	end
	if #texts > 0 then
		answer = vim.split(table.concat(texts, "\n\n"), "\n", { plain = true })
	end
	return session_id, answer, failure
end

return M
