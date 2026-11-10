local catalog = require("agents.ephemeral.catalog")
local constants = require("agents.constants")
local preferences = require("agents.ephemeral.preferences")
local util = require("agents.util")

local M = {}
local generation = 0

-- A picker belongs to the project and selection revision that opened it.
-- Switching away and back must not revive a stale discovery/input callback.
local function request_is_current(request, id)
	local selection = require("agents.selection")
	local project = selection.project()
	local revision = selection.revision(project)
	return function()
		return request == generation
			and selection.project() == project
			and selection.get(project) == id
			and selection.revision(project) == revision
	end
end
local cancel_discovery

M.load = preferences.load

function M.get(action, id)
	return M.load(id)[action]
end

function M.display(model)
	return model and model ~= "" and model or "CLI default"
end

function M.action_label(action)
	if action == "edit" then
		return "edits"
	end
	if action == "query" then
		return "queries"
	end
	if action == "commit" then
		return "commit messages"
	end
	return "jobs"
end

function M.set(action, model, id)
	id = id or require("agents.selection").get()
	if action ~= "edit" and action ~= "query" and action ~= "commit" then
		util.notify("Unknown Agent model target: " .. tostring(action), vim.log.levels.WARN)
		return
	end
	local models = M.load(id)
	model = util.trim_whitespace(model)
	models[action] = model ~= "" and model or nil
	preferences.save(action, models[action], id)
	util.notify(id .. " " .. M.action_label(action) .. " model: " .. M.display(models[action]))
end

local function prompt_custom_model(action, current, id)
	vim.ui.input({
		prompt = id .. " " .. M.action_label(action) .. " model: ",
		default = M.get(action, id) or "",
	}, function(model)
		if current() and model ~= nil and util.trim_whitespace(model) ~= "" then
			M.set(action, model, id)
		end
	end)
end

local function choices_for(action, models, id)
	local choices = { { label = "CLI default" } }
	local current = M.get(action, id)
	local listed = false
	for _, choice in ipairs(models) do
		listed = listed or choice.model == current
		table.insert(choices, choice)
	end
	if current and not listed then
		table.insert(choices, 2, { label = current .. " (unlisted)", model = current })
	end
	table.insert(choices, { label = "Custom…", custom = true })
	return choices
end

local function invalidate()
	generation = generation + 1
	if cancel_discovery then
		cancel_discovery()
		cancel_discovery = nil
	end
	return generation
end

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("opencode-model-discovery", { clear = true }),
	callback = invalidate,
})

function M.select(action)
	if action ~= "edit" and action ~= "query" and action ~= "commit" then
		util.notify("Usage: AgentEphemeralModel [query|edit|commit]", vim.log.levels.WARN)
		return
	end
	M.load()
	local request = invalidate()
	local id = require("agents.selection").get()
	local current = request_is_current(request, id)
	util.notify("Loading " .. id .. " models…")
	cancel_discovery = catalog.fetch(function(models, source, err)
		if not current() then
			return
		end
		cancel_discovery = nil
		if err then
			util.notify(
				id
					.. " model discovery failed: "
					.. err
					.. (source == "cached" and "; using cached choices" or "; use CLI default or a custom model"),
				vim.log.levels.WARN
			)
		end
		vim.ui.select(choices_for(action, models, id), {
			prompt = id .. " " .. M.action_label(action) .. " model" .. (source == "cached" and " (cached)" or ""),
			format_item = function(choice)
				local selected = not choice.custom and M.get(action, id) == choice.model
				return choice.label .. (selected and " (current)" or "")
			end,
		}, function(choice)
			if not choice or not current() then
				return
			end
			if choice.custom then
				prompt_custom_model(action, current, id)
			else
				M.set(action, choice.model, id)
			end
		end)
	end, id)
end

function M.select_target()
	M.load()
	local request = invalidate()
	local id = require("agents.selection").get()
	local current = request_is_current(request, id)
	vim.ui.select(constants.EPHEMERAL_MODEL_TARGETS, {
		prompt = id .. " model target (background jobs)",
		format_item = function(target)
			return target.label .. " (" .. M.display(M.get(target.action, id)) .. ")"
		end,
	}, function(target)
		if target and current() then
			M.select(target.action)
		end
	end)
end

return M
