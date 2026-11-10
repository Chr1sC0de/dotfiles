-- Shared process boundary. Always capture backend ownership before async work.
local M = {}

function M.get(id)
	id = id or require("agents.selection").get()
	assert(require("agents.selection").valid(id), "Unknown agent backend: " .. tostring(id))
	return require("agents.backends." .. id)
end

function M.plugin_path()
	return M.get("opencode").plugin_path()
end
function M.environment(config, opts)
	return M.get(opts and opts.backend).environment(config, opts)
end
function M.run_args(opts)
	return M.get(opts and opts.backend).run_args(opts)
end
function M.interactive_args(session)
	return M.get(session.backend or "opencode").interactive_args(session)
end
function M.parse_events(lines, id)
	return M.get(id or "opencode").parse_events(lines)
end

function M.generate(prompt, cwd, callback, model, id)
	id = id or require("agents.selection").get()
	local adapter = M.get(id)
	local env, err = adapter.environment(nil, { text_only = true })
	if not env then
		callback(1, "", err)
		return nil
	end
	env.PWD = cwd or vim.fn.getcwd()
	local stdout, stderr = {}, {}
	local job = vim.fn.jobstart(adapter.run_args({ model = model, text_only = true }), {
		cwd = cwd,
		env = env,
		stdin = "pipe",
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			vim.list_extend(stdout, data or {})
		end,
		on_stderr = function(_, data)
			vim.list_extend(stderr, data or {})
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				local _, answer, failure = adapter.parse_events(stdout)
				callback(failure and 1 or code, table.concat(answer or {}, "\n"), failure or table.concat(stderr, "\n"))
			end)
		end,
	})
	if job <= 0 then
		callback(1, "", "failed to start " .. id)
		return nil
	end
	vim.fn.chansend(job, prompt)
	vim.fn.chanclose(job, "stdin")
	return job
end

return M
