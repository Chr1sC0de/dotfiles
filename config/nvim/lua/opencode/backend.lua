-- OpenCode V2 process boundary. Private servers keep launch-specific Tandem
-- connections and restrictions out of the user's shared background service.
local M = {}

function M.plugin_path()
	return vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/../../opencode-plugin"
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
	merged.policies = vim.deepcopy(inherited.policies or {})
	table.insert(merged.policies, { action = "tool.use", resource = "*", effect = "deny" })
	if not opts.text_only then
		local actions = { "read", "glob", "grep", "webfetch", "websearch", "question", "external_directory", "nvim_shell",
			"tandem_tandem_read_file", "tandem_tandem_status" }
		if not opts.read_only then table.insert(actions, "tandem_tandem_write_file") end
		for _, action in ipairs(actions) do
			table.insert(merged.policies, { action = "tool.use", resource = action .. ":*", effect = "allow" })
		end
	end
	merged.plugins = vim.deepcopy(inherited.plugins or {})
	table.insert(merged.plugins, { package = M.plugin_path(), options = {
		read_only = opts.read_only == true,
		text_only = opts.text_only == true,
		root = opts.root,
		gateway = config and config.mcp and config.mcp.servers.tandem,
	} })
	return { OPENCODE_CONFIG_CONTENT = vim.json.encode(merged) }
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
			if type(event.sessionID) == "string" then session_id = event.sessionID end
			if event.type == "text" and type(event.part) == "table" and type(event.part.text) == "string" then
				table.insert(texts, event.part.text)
			elseif event.type == "error" then
				failure = vim.json.encode(event.error or event)
			end
		end
	end
	if #texts > 0 then answer = vim.split(table.concat(texts, "\n\n"), "\n", { plain = true }) end
	return session_id, answer, failure
end

-- Titles, branch names and commit subjects never need tools. Reuse the same
-- streaming decoder so terminal decorations cannot become generated content.
function M.generate(prompt, cwd, callback, model)
	local env, err = M.environment(nil, { text_only = true })
	if not env then callback(1, "", err); return nil end
	env.PWD = cwd or vim.fn.getcwd()
	local stdout, stderr = {}, {}
	local job = vim.fn.jobstart(M.run_args({ model = model }), {
		cwd = cwd, env = env, stdin = "pipe", stdout_buffered = true, stderr_buffered = true,
		on_stdout = function(_, data) vim.list_extend(stdout, data or {}) end,
		on_stderr = function(_, data) vim.list_extend(stderr, data or {}) end,
		on_exit = function(_, code)
			vim.schedule(function()
				local _, answer, failure = M.parse_events(stdout)
				callback(failure and 1 or code, table.concat(answer or {}, "\n"), failure or table.concat(stderr, "\n"))
			end)
		end,
	})
	if job <= 0 then callback(1, "", "failed to start OpenCode"); return nil end
	vim.fn.chansend(job, prompt)
	vim.fn.chanclose(job, "stdin")
	return job
end

return M
