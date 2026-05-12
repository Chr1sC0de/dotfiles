local util = require("workmux.util")

local M = {}

---Prompt for non-empty user input.
---
---@param prompt string
---@param callback fun(value: string)
function M.input(prompt, callback)
	vim.ui.input({ prompt = prompt }, function(value)
		value = util.trim(value)
		if value == "" then
			return
		end

		callback(value)
	end)
end

---Require an exact typed confirmation before running a destructive action.
---
---@param expected string Confirmation text the user must type exactly.
---@param action string Human-readable action label for the prompt.
---@param callback fun()
function M.confirm_exact(expected, action, callback)
	vim.ui.input({ prompt = "Type `" .. expected .. "` to " .. action .. ": " }, function(value)
		if value == nil then
			return
		end
		if value ~= expected then
			util.notify(action .. " cancelled: confirmation did not match", vim.log.levels.WARN)
			return
		end

		callback()
	end)
end

return M
