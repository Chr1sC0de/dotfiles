local M = {}

---Show a namespaced Workmux notification.
---
---@param message string
---@param level? integer `vim.log.levels` value.
function M.notify(message, level)
	vim.notify("workmux: " .. message, level or vim.log.levels.INFO)
end

---Trim leading and trailing whitespace from optional user or process text.
---
---@param value? string
---@return string
function M.trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

return M
