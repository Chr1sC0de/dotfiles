local state = require("opencode.state")
local util = require("opencode.util")

local M = {}

function M.path()
	return util.join_path(vim.fn.stdpath("state"), "opencode/ephemeral-models.json")
end

local function read()
	local path = M.path()
	local stat, err = vim.uv.fs_stat(path)
	if not stat and err and err:find("ENOENT", 1, true) then
		return {}
	end
	local ok, value = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
	end)
	if not ok or type(value) ~= "table" then
		util.notify("Could not read OpenCode model preferences: " .. path, vim.log.levels.WARN)
		return {}
	end
	local models = {}
	for _, action in ipairs({ "query", "edit", "commit" }) do
		local model = value[action]
		if type(model) == "string" then
			model = util.trim_whitespace(model)
			models[action] = model ~= "" and model or nil
		elseif model ~= nil and model ~= vim.NIL then
			util.notify("Ignoring invalid OpenCode " .. action .. " model preference", vim.log.levels.WARN)
		end
	end
	return models
end

function M.load()
	if state.ephemeral_models_loaded then
		return
	end
	state.ephemeral_models = read()
	state.ephemeral_models_loaded = true
end

function M.save(action, model)
	local path = M.path()
	local temporary = path .. ".tmp." .. vim.fn.getpid() .. "." .. tostring(vim.uv.hrtime())
	local ok, err = pcall(function()
		-- Preserve other actions if another Neovim session has saved them.
		local models = read()
		models[action] = model
		local saved = { query = models.query or vim.NIL, edit = models.edit or vim.NIL, commit = models.commit or vim.NIL }
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p", 448)
		if vim.fn.writefile({ vim.json.encode(saved) }, temporary, "s") ~= 0 then
			error("could not write preferences")
		end
		local renamed, rename_err = vim.uv.fs_rename(temporary, path)
		if not renamed then
			error(rename_err or "could not replace preferences")
		end
	end)
	if not ok then
		pcall(vim.fn.delete, temporary)
		util.notify(
			"Could not save OpenCode model preference; selection applies to this session only: " .. tostring(err),
			vim.log.levels.WARN
		)
	end
	return ok
end

return M
