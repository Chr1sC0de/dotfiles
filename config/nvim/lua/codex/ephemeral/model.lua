local catalog = require("codex.ephemeral.catalog")
local constants = require("codex.constants")
local preferences = require("codex.ephemeral.preferences")
local state = require("codex.state")
local util = require("codex.util")

local M = {}
local generation = 0
local cancel_discovery

M.load = preferences.load

function M.get(action)
	M.load()
	return state.ephemeral_models[action]
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
	return "jobs"
end

function M.set(action, model)
	if action ~= "edit" and action ~= "query" then
		util.notify("Unknown Codex model target: " .. tostring(action), vim.log.levels.WARN)
		return
	end
	M.load()
	model = util.trim_whitespace(model)
	state.ephemeral_models[action] = model ~= "" and model or nil
	preferences.save(action, state.ephemeral_models[action])
	util.notify("Codex " .. M.action_label(action) .. " model: " .. M.display(state.ephemeral_models[action]))
end

local function prompt_custom_model(action, request)
	vim.ui.input({
		prompt = "Codex " .. M.action_label(action) .. " model: ",
		default = M.get(action) or "",
	}, function(model)
		if request == generation and model ~= nil and util.trim_whitespace(model) ~= "" then
			M.set(action, model)
		end
	end)
end

local function choices_for(action, models)
	local choices = { { label = "CLI default" } }
	local current = M.get(action)
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
	group = vim.api.nvim_create_augroup("codex-model-discovery", { clear = true }),
	callback = invalidate,
})

function M.select(action)
	if action ~= "edit" and action ~= "query" then
		util.notify("Usage: CodexEphemeralModel [query|edit]", vim.log.levels.WARN)
		return
	end
	M.load()
	local request = invalidate()
	util.notify("Loading Codex models…")
	cancel_discovery = catalog.fetch(function(models, source, err)
		if request ~= generation then
			return
		end
		cancel_discovery = nil
		if err then
			util.notify(
				"Codex model discovery failed: "
					.. err
					.. (source == "cached" and "; using cached choices" or "; use CLI default or a custom model"),
				vim.log.levels.WARN
			)
		end
		vim.ui.select(choices_for(action, models), {
			prompt = "Codex " .. M.action_label(action) .. " model" .. (source == "cached" and " (cached)" or ""),
			format_item = function(choice)
				local current = not choice.custom and M.get(action) == choice.model
				return choice.label .. (current and " (current)" or "")
			end,
		}, function(choice)
			if not choice or request ~= generation then
				return
			end
			if choice.custom then
				prompt_custom_model(action, request)
			else
				M.set(action, choice.model)
			end
		end)
	end)
end

function M.select_target()
	M.load()
	local request = invalidate()
	vim.ui.select(constants.EPHEMERAL_MODEL_TARGETS, {
		prompt = "Codex model target",
		format_item = function(target)
			return target.label .. " (" .. M.display(M.get(target.action)) .. ")"
		end,
	}, function(target)
		if target and request == generation then
			M.select(target.action)
		end
	end)
end

return M
