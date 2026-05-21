local chat = require("codex.chat")
local util = require("codex.util")

local M = {}

local function build_selection_entries(oil, bufnr, directory, start_line, end_line)
	local entries = {}
	local seen_paths = {}

	for line = start_line, end_line do
		local entry = oil.get_entry_on_line(bufnr, line)
		local name = entry and util.trim_whitespace(entry.parsed_name or entry.name)

		if name and name ~= "" then
			local path = util.join_path(directory, name)
			if not seen_paths[path] then
				seen_paths[path] = true
				table.insert(entries, {
					path = util.repo_relative_path(path),
					type = entry.type or "unknown",
				})
			end
		end
	end

	return entries
end

function M.send_selection_context(text, start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].filetype ~= "oil" then
		return false
	end

	local ok, oil = pcall(require, "oil")
	if not ok then
		return false
	end

	local directory = oil.get_current_dir(bufnr)
	if not directory then
		return false
	end

	local entries = build_selection_entries(oil, bufnr, directory, start_line, end_line)
	if #entries == 0 then
		return false
	end

	local entry_lines = {}
	for _, entry in ipairs(entries) do
		table.insert(entry_lines, "- " .. entry.path .. " [" .. entry.type .. "]")
	end

	local prompt_lines = {
		"Use this Oil directory selection as context for the current Codex chat.",
		"",
		"Directory: " .. util.repo_relative_path(directory),
		"Lines: " .. start_line .. "-" .. end_line,
		"Filetype: oil",
		"Unsaved Oil changes: " .. (vim.bo[bufnr].modified and "yes" or "no"),
		"",
		"Selected filesystem entries:",
	}
	vim.list_extend(prompt_lines, entry_lines)
	vim.list_extend(prompt_lines, {
		"",
		"These entries came from an Oil directory buffer. Read files or directories from disk if needed.",
		"",
		"Raw Oil selection:",
		"```oil",
		text,
		"```",
	})

	if chat.paste(table.concat(prompt_lines, "\n")) then
		util.notify(
			"Sent Oil selection to Codex: "
				.. util.repo_relative_path(directory)
				.. ":"
				.. start_line
				.. "-"
				.. end_line
		)
	end

	return true
end

return M
