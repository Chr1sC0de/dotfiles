local constants = require("codex.constants")
local state = require("codex.state")
local util = require("codex.util")

local M = {}

function M.display(model)
	return model and model ~= "" and model or "CLI default"
end

function M.action_label(action)
	if action == "edit" then
		return "ephemeral edits"
	end
	if action == "command" then
		return "ephemeral commands"
	end

	return "ephemeral jobs"
end

function M.set(action, model)
	if action ~= "edit" and action ~= "command" then
		util.notify("Unknown Codex ephemeral model target: " .. tostring(action), vim.log.levels.WARN)
		return
	end

	model = util.trim_whitespace(model)
	state.ephemeral_models[action] = model ~= "" and model or nil
	util.notify("Codex " .. M.action_label(action) .. " model: " .. M.display(state.ephemeral_models[action]))
end

local function prompt_custom_ephemeral_model(action)
	vim.ui.input({
		prompt = "Codex " .. M.action_label(action) .. " model: ",
		default = state.ephemeral_models[action] or "",
	}, function(model)
		if model == nil then
			return
		end

		model = util.trim_whitespace(model)
		if model == "" then
			util.notify("Codex " .. M.action_label(action) .. " model unchanged")
			return
		end

		M.set(action, model)
	end)
end

local function ephemeral_model_choices(action)
	local choices = {}
	local current_model = state.ephemeral_models[action]
	local current_is_preset = false

	for _, choice in ipairs(constants.EPHEMERAL_MODEL_CHOICES) do
		if not choice.custom and choice.model == current_model then
			current_is_preset = true
			break
		end
	end

	if current_model and not current_is_preset then
		table.insert(choices, { label = current_model, model = current_model, current = true })
	end

	vim.list_extend(choices, constants.EPHEMERAL_MODEL_CHOICES)
	return choices
end

function M.select(action)
	if action ~= "edit" and action ~= "command" then
		util.notify("Usage: CodexEphemeralModel [edit|command]", vim.log.levels.WARN)
		return
	end

	vim.ui.select(ephemeral_model_choices(action), {
		prompt = "Codex "
			.. M.action_label(action)
			.. " model (current: "
			.. M.display(state.ephemeral_models[action])
			.. ")",
		format_item = function(choice)
			if choice.current then
				return choice.label .. " (current)"
			end

			if choice.custom then
				return choice.label
			end

			local suffix = state.ephemeral_models[action] == choice.model and " (current)" or ""
			return choice.label .. suffix
		end,
	}, function(choice)
		if not choice then
			return
		end

		if choice.custom then
			prompt_custom_ephemeral_model(action)
			return
		end

		M.set(action, choice.model)
	end)
end

function M.select_target()
	vim.ui.select(constants.EPHEMERAL_MODEL_TARGETS, {
		prompt = "Codex ephemeral model target",
		format_item = function(target)
			return target.label .. " (" .. M.display(state.ephemeral_models[target.action]) .. ")"
		end,
	}, function(target)
		if target then
			M.select(target.action)
		end
	end)
end

return M
