-- Persist identities, not terminal buffers or credentials. Each checkout has
-- its own record so separate worktrees and Neovim instances do not collide.
local M = {}

function M.project()
	local path = vim.fn.getcwd()
	local buf = vim.api.nvim_get_current_buf()
	if vim.bo[buf].buftype == "" then
		local name = vim.api.nvim_buf_get_name(buf)
		if name ~= "" then path = vim.fs.dirname(name) end
	end
	path = vim.fs.root(path, ".git") or path
	return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function path(project)
	return vim.fn.stdpath("state") .. "/opencode/attachments/" .. vim.fn.sha256(project) .. ".json"
end

function M.load(project)
	local filename = path(project)
	if not vim.uv.fs_stat(filename) then return nil end
	local ok, record = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(filename), "\n"))
	end)
	if ok and type(record) == "table" and record.project == project
		and type(record.name) == "string" and type(record.pane_id) == "string"
		and type(record.workspace_id) == "string" then
		return record
	end
	require("opencode.util").notify("Could not read remembered OpenCode attachment", vim.log.levels.WARN)
end

function M.matches(record, agent)
	return agent and agent.agent == "opencode" and record.name == (agent.name or agent.pane_id)
		and record.pane_id == agent.pane_id and record.workspace_id == agent.workspace_id
end

function M.save(project, session)
	if not session.herdr_agent_name or not session.herdr_pane_id or not session.herdr_workspace_id then return end
	local filename = path(project)
	local temporary = filename .. ".tmp." .. vim.fn.getpid() .. "." .. vim.uv.hrtime()
	local ok, err = pcall(function()
		vim.fn.mkdir(vim.fs.dirname(filename), "p", 448)
		local record = { project = project, name = session.herdr_agent_name,
			pane_id = session.herdr_pane_id, workspace_id = session.herdr_workspace_id }
		assert(vim.fn.writefile({ vim.json.encode(record) }, temporary, "s") == 0, "write failed")
		assert(vim.uv.fs_rename(temporary, filename))
	end)
	if not ok then
		pcall(vim.fn.delete, temporary)
		require("opencode.util").notify("Could not remember OpenCode attachment: " .. tostring(err), vim.log.levels.WARN)
	end
end

return M
