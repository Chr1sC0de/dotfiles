-- Legacy state paths are intentional: preserve preferences and identities on upgrade.
-- Persist identities, not terminal buffers or credentials. Each checkout has
-- its own record so separate worktrees and Neovim instances do not collide.
local M = {}

function M.project()
	local path = vim.fn.getcwd()
	local buf = vim.api.nvim_get_current_buf()
	if vim.bo[buf].buftype == "" then
		local name = vim.api.nvim_buf_get_name(buf)
		if name ~= "" then
			path = vim.fs.dirname(name)
		end
	end
	-- A .git path alone is not proof of a repository (for example, an empty
	-- directory left behind by tooling). Ask Git so source and terminal
	-- buffers agree, while preserving real nested repositories and worktrees.
	if vim.fn.executable("git") == 1 then
		local result = vim.system({ "git", "-C", path, "rev-parse", "--show-toplevel" }, { text = true }):wait()
		if result.code == 0 then
			path = vim.trim(result.stdout)
		end
	else
		path = vim.fs.root(path, ".git") or path
	end
	return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function path(project, backend)
	local suffix = backend and backend ~= "opencode" and ("-" .. backend) or ""
	return vim.fn.stdpath("state") .. "/opencode/attachments/" .. vim.fn.sha256(project) .. suffix .. ".json"
end

function M.load(project, backend)
	local filename = path(project, backend)
	if not vim.uv.fs_stat(filename) then
		return nil
	end
	local ok, record = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(filename), "\n"))
	end)
	if
		ok
		and type(record) == "table"
		and record.project == project
		and (record.backend or "opencode") == (backend or "opencode")
		and type(record.name) == "string"
		and type(record.pane_id) == "string"
		and type(record.workspace_id) == "string"
	then
		return record
	end
	require("agents.util").notify("Could not read remembered Agent attachment", vim.log.levels.WARN)
end

function M.matches(record, agent)
	return agent
		and agent.agent == (record.backend or "opencode")
		and record.name == (agent.name or agent.pane_id)
		and record.pane_id == agent.pane_id
		and record.workspace_id == agent.workspace_id
end

function M.save(project, session)
	if not session.herdr_agent_name or not session.herdr_pane_id or not session.herdr_workspace_id then
		return
	end
	local filename = path(project, session.backend)
	local temporary = filename .. ".tmp." .. vim.fn.getpid() .. "." .. vim.uv.hrtime()
	local ok, err = pcall(function()
		vim.fn.mkdir(vim.fs.dirname(filename), "p", 448)
		local record = {
			project = project,
			backend = session.backend or "opencode",
			name = session.herdr_agent_name,
			pane_id = session.herdr_pane_id,
			workspace_id = session.herdr_workspace_id,
		}
		assert(vim.fn.writefile({ vim.json.encode(record) }, temporary, "s") == 0, "write failed")
		assert(vim.uv.fs_rename(temporary, filename))
	end)
	if not ok then
		pcall(vim.fn.delete, temporary)
		require("agents.util").notify("Could not remember Agent attachment: " .. tostring(err), vim.log.levels.WARN)
	end
end

return M
