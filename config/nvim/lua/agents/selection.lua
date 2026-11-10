-- Legacy state paths are intentional: preserve preferences and identities on upgrade.
-- Backend selection is project-local; processes and callbacks retain ownership.
local M = {}
local selected, last, revisions = {}, {}, {}
M.ids = { "opencode", "pi" }

function M.project()
	return require("agents.attachment").project()
end

local function path(project)
	return vim.fn.stdpath("state") .. "/opencode/backends/" .. vim.fn.sha256(project) .. ".json"
end

function M.valid(id)
	return id == "opencode" or id == "pi"
end

function M.get(project)
	project = project or M.project()
	if not selected[project] then
		local ok, record = pcall(function()
			return vim.json.decode(table.concat(vim.fn.readfile(path(project)), "\n"))
		end)
		selected[project] = ok
				and type(record) == "table"
				and record.project == project
				and M.valid(record.backend)
				and record.backend
			or "opencode"
	end
	return selected[project]
end

function M.set(id, project)
	assert(M.valid(id), "Unknown agent backend: " .. tostring(id))
	project = project or M.project()
	selected[project] = id
	revisions[project] = (revisions[project] or 0) + 1
	local filename = path(project)
	local temporary = filename .. ".tmp." .. vim.fn.getpid() .. "." .. vim.uv.hrtime()
	local ok, err = pcall(function()
		vim.fn.mkdir(vim.fs.dirname(filename), "p", 448)
		assert(vim.fn.writefile({ vim.json.encode({ project = project, backend = id }) }, temporary, "s") == 0)
		assert(vim.uv.fs_rename(temporary, filename))
	end)
	if not ok then
		pcall(vim.fn.delete, temporary)
		require("agents.util").notify("Backend applies in this instance only: " .. tostring(err), vim.log.levels.WARN)
	end
end

function M.revision(project)
	return revisions[project or M.project()] or 0
end

function M.remember(session)
	local project = session.project or M.project()
	last[project] = last[project] or {}
	last[project][session.backend or "opencode"] = session.bufnr
end

function M.last(project, id)
	return last[project] and last[project][id]
end

local function session_path(project, id)
	return path(project):gsub("%.json$", "-" .. id .. "-session.json")
end

function M.resume(project, id)
	local ok, record = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(session_path(project, id)), "\n"))
	end)
	if
		ok
		and type(record) == "table"
		and record.project == project
		and record.backend == id
		and type(record.session_id) == "string"
	then
		return type(record.session_path) == "string" and record.session_path or record.session_id
	end
end

function M.remember_native(session)
	if not session.project or not session.native_session_id or session.external_attachment then
		return
	end
	local filename = session_path(session.project, session.backend or "opencode")
	local temporary = filename .. ".tmp." .. vim.fn.getpid() .. "." .. vim.uv.hrtime()
	local ok = pcall(function()
		vim.fn.mkdir(vim.fs.dirname(filename), "p", 448)
		assert(vim.fn.writefile({
			vim.json.encode({
				project = session.project,
				backend = session.backend or "opencode",
				session_id = session.native_session_id,
				session_path = session.native_session_path,
			}),
		}, temporary, "s") == 0)
		assert(vim.uv.fs_rename(temporary, filename))
	end)
	if not ok then
		pcall(vim.fn.delete, temporary)
	end
end

function M.command(opts)
	local project = M.project()
	local revision = M.revision(project)
	local function choose(id)
		if id and M.project() == project and M.revision(project) == revision then
			require("agents.chat").switch_backend(id)
		end
	end
	local id = opts and opts.args or ""
	if id ~= "" then
		choose(id)
		return
	end
	vim.ui.select(M.ids, { prompt = "Agent backend (current: " .. M.get() .. ")" }, choose)
end

return M
